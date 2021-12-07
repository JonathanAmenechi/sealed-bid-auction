import hre, { deployments, ethers } from "hardhat";

import { deploy, hardhatFastForward } from "./helpers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { TestToken, Test721, SealedBidAuctionFactory, SealedBidAuction } from "../typechain";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const deployer = signers[0];
    const bidderA = signers[1];
    const bidderB = signers[2];
    const bidderC = signers[3]; 
    
    const bidToken: TestToken = <TestToken>await deploy("TestToken", 
        { from: deployer.address, args: [] }
    );

    const testNFT: Test721 = <Test721>await deploy("Test721",
        { from: deployer.address, args: [] }
    );

    // Mint test tokens
    await( await bidToken.mint(deployer.address, ethers.utils.parseEther("1000"))).wait();
    await( await bidToken.mint(bidderA.address, ethers.utils.parseEther("1000"))).wait();
    await( await bidToken.mint(bidderB.address, ethers.utils.parseEther("1000"))).wait();
    await( await testNFT.mint(deployer.address, 0)).wait();

    // Deploy factory
    const factory: SealedBidAuctionFactory = <SealedBidAuctionFactory>await deploy("SealedBidAuctionFactory", 
    {
        from: deployer.address,
        args: []
    });

    // approve testNFT on factory
    await(await testNFT.approve(factory.address, 0)).wait();

    // deploy auction
    const nonce = await factory.nonce();
    const expectedAuctionAddress = await factory.connect(deployer).computeAuctionAddress(
        factory.address, deployer.address, bidToken.address, testNFT.address, 0, 3600, 3600, 0, nonce);

    await( await factory.connect(deployer).deployAuction(
        bidToken.address, testNFT.address, 0, 3600, 3600, 0)
    ).wait();

    const auction: SealedBidAuction = <SealedBidAuction>await ethers.getContractAt("SealedBidAuction", expectedAuctionAddress, deployer);

    // Max approve test tokens on auction
    await( await bidToken.connect(deployer).approve(auction.address, ethers.constants.MaxUint256)).wait();
    await( await bidToken.connect(bidderA).approve(auction.address, ethers.constants.MaxUint256)).wait();
    await( await bidToken.connect(bidderB).approve(auction.address, ethers.constants.MaxUint256)).wait();
    await( await bidToken.connect(bidderC).approve(auction.address, ethers.constants.MaxUint256)).wait();


    return {
        deployer,
        bidToken,
        testNFT,
        auction,
    };
});


interface Commitment {
    bidder: string;
    bidAmount: string;
    secret: Uint8Array;
    commitment: string;
}


describe("Sealed Bid Auction tests", function () {
    let deployer: SignerWithAddress;
    let bidToken: TestToken;
    let testNFT: Test721;
    let auction: SealedBidAuction;
    let commitments: Map<string, Commitment>;

    before(async function () {
        const set = await setup();
        deployer = set.deployer;
        bidToken = set.bidToken;
        testNFT = set.testNFT;
        auction = set.auction;
        commitments = new Map();
    });

    it("should allow the auction owner to start the auction", async function () {
        // pre auction start, AuctionPhase should be INACTIVE("0")
        const auctionPhase = await auction.currentPhase();
        expect(auctionPhase).to.be.eq(0);

        // Only the auction owner should be able to start an auction
        const nonOwnerSigner = (await hre.ethers.getSigners())[5];
        await expect(
            auction.connect(nonOwnerSigner).startAuction(),
        ).to.be.revertedWith("Ownable: caller is not the owner");

        // Start auction and move auction phase to COMMIT("1")
        await( await auction.connect(deployer).startAuction()).wait();
        const currentPhase = await auction.currentPhase();
        expect(currentPhase).to.be.eq(1);
    });

    it("should create sealed bids on the auction", async function () {        
        // generate commitment hashes for 4 bidders
        const bids = ["1", "0.5", "3", "1000"];
        for(let i =0; i<4; i++){
            const bidder = (await hre.ethers.getSigners())[i];
            const bid = ethers.utils.parseEther(bids[i]);
            const secret = ethers.utils.randomBytes(32);
            const commitment = await auction.createCommitment(bidder.address, bid, secret);
            
            // Push the commitment hashes
            await( await auction.connect(bidder).commit(commitment)).wait();
            
            // Assert that the commitment has been received
            expect((await auction.commitments(commitment))).to.be.true;

            commitments.set(bidder.address, {
                bidder: bidder.address,
                bidAmount: bid.toString(),
                secret,
                commitment,
            });
        }
    });

    it("should revert if COMMIT period hasn't elapsed", async function () {        
        await expect(
            auction.startRevealPhase(),
        ).to.be.revertedWith("Auction::commit phase has not ended");
    });

    it("should move the auction to the REVEAL phase after commit period has elapsed", async function () {        
        // Fast forward past the COMMIT period
        await hardhatFastForward(3600);

        // Anyone can start the REVEAL phase
        const signer = ethers.Wallet.createRandom().connect(ethers.provider);
        await(await deployer.sendTransaction({to: signer.address, value: ethers.utils.parseEther("1")})).wait();
        await auction.connect(signer).startRevealPhase();

        const currentPhase = await auction.currentPhase();
        expect(currentPhase).to.be.eq(2);
    });

    it("should revert if bidder does not have enough tokens to fulfill their commitment", async function () {        
        const negligentBidder = (await hre.ethers.getSigners())[3];
        const storedCommitment = await commitments.get(negligentBidder.address) as Commitment;
        
        // negligent bidder does not have enough BidToken to fill his bid
        const bidTokenBalance = await bidToken.balanceOf(negligentBidder.address);
        expect(bidTokenBalance).to.be.eq("0");
        
        // Attempt to reveal bid reverts
        await expect(
            auction.connect(negligentBidder).reveal(storedCommitment.bidAmount, storedCommitment.secret),
        ).to.be.revertedWith("TransferHelper::STF");
        
    });

    it("should allow bidders reveal their bids", async function () {        
        // Reveal first bid
        const bidderA = (await hre.ethers.getSigners())[0];
        const storedCommitment = await commitments.get(bidderA.address) as Commitment;
        // Assert highest bid event 
        void expect(
            await auction.connect(bidderA).
            reveal(storedCommitment.bidAmount, storedCommitment.secret))
            .to.emit(auction, "NewHighestBid")
            .withArgs(
                bidderA.address,
                storedCommitment.bidAmount,
                ethers.constants.AddressZero,
                ethers.constants.Zero
            );

        // Assert tokens transferred from the bidder to the Auction
        const bidTokenBalanceOnAuction = await bidToken.balanceOf(auction.address);
        expect(bidTokenBalanceOnAuction.toString()).to.eq(storedCommitment.bidAmount)
        
        // Reveal remaining bids
        for(let i =1; i<3; i++){
            const bidder = (await hre.ethers.getSigners())[i];
            const storedCommitment = await commitments.get(bidder.address) as Commitment;
            await( await auction.connect(bidder).reveal(storedCommitment.bidAmount, storedCommitment.secret)).wait();
        }     
    });

    it("should revert if finalize is called before REVEAL phase has elapsed", async function () {        
        await expect(
            auction.finalize(),
        ).to.be.revertedWith("Auction::reveal phase has not ended");
    });

    it("should finalize the auction", async function () {        
        // Fast forward past the REVEAL period
        await hardhatFastForward(3600);

        const auctionOwner = await auction.owner();
        const bidTokenBalancePreFinalize = await bidToken.balanceOf(auctionOwner);

        const highestBidder = await auction.highestBidder();
        const highestBid = await auction.highestBid();

        // Anyone can finalize the auction
        const signer = ethers.Wallet.createRandom().connect(ethers.provider);
        await(await deployer.sendTransaction({to: signer.address, value: ethers.utils.parseEther("1")})).wait();
    
        void expect( 
            await auction.connect(signer).
                finalize()
            ).to.emit(auction, "Finalized")
            .withArgs(
                signer.address,
                highestBidder,
                highestBid.toString()
            );

        // Assert that Auction phase is now Finalized
        const currentPhase = await auction.currentPhase();
        expect(currentPhase).to.be.eq(3);

        // Assert the highest bidder now owns the auctioned token
        expect(await testNFT.ownerOf(0)).to.be.eq(highestBidder);

        // Assert bidTokens have been transferred to the auction owner
        const bidTokenBalancePostFinalize = await bidToken.balanceOf(auctionOwner);
        expect(bidTokenBalancePostFinalize.toString()).to.be.eq(bidTokenBalancePreFinalize.add(highestBid).toString())
    });

});
