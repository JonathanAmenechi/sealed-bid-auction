import hre, { deployments, ethers } from "hardhat";

import { deploy } from "./helpers";
import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";
import { TestToken, Test721, SealedBidAuctionFactory, SealedBidAuction } from "../typechain";

const setup = deployments.createFixture(async () => {
    const signers = await hre.ethers.getSigners();
    const deployer = signers[0];
    
    const bidToken: TestToken = <TestToken>await deploy("TestToken", 
        { from: deployer.address, args: [] }
    );

    const test721: Test721 = <Test721>await deploy("Test721",
        { from: deployer.address, args: [] }
    );

    // Mint test tokens
    await( await bidToken.mint(deployer.address, ethers.utils.parseEther("1000"))).wait();
    await( await test721.mint(deployer.address, 0)).wait();

    // Deploy factory
    const factory: SealedBidAuctionFactory = <SealedBidAuctionFactory>await deploy("SealedBidAuctionFactory", 
    {
        from: deployer.address,
        args: []
    });

    // approve test 721 on factory
    await(await test721.approve(factory.address, 0)).wait();

    // deploy auction
    const nonce = await factory.nonce();
    const expectedAuctionAddress = await factory.connect(deployer).computeAuctionAddress(
        factory.address, deployer.address, bidToken.address, test721.address, 0, 3600, 3600, 0, nonce);

    await( await factory.connect(deployer).deployAuction(
        bidToken.address, test721.address, 0, 3600, 3600, 0)
    ).wait();

    const auction: SealedBidAuction = <SealedBidAuction>await ethers.getContractAt("SealedBidAuction", expectedAuctionAddress, deployer);

    return {
        deployer,
        auction,
    };
});



describe("Sealed Bid Auction tests", function () {
    let deployer: SignerWithAddress;
    let auction: SealedBidAuction;

    before(async function () {
        const set = await setup();
        deployer = set.deployer;
        auction = set.auction;
    });

    it("should allow the auction owner to start the auction", async function () {
        // pre auction start, AuctionPhase should be INACTIVE("0")
        const auctionPhase = await auction.currentPhase();
        expect(auctionPhase).to.be.eq(0);

        // Only the auction owner should be able to start an auction
        const nonOwnerSigner = (await hre.ethers.getSigners())[5];
        await expect(
            auction.connect(nonOwnerSigner).startAuction(),
        ).to.be.revertedWith("Ownable: caller is not the owner")

        // Start auction and move auction phase to COMMIT("1")
        await( await auction.connect(deployer).startAuction()).wait();
        const currentPhase = await auction.currentPhase();
        expect(currentPhase).to.be.eq(1);
    });


    it("should create sealed bids on the auction", async function () {        
        // generate commitment hashes
        for(let i =0; i<3; i++){
            const bidder = (await hre.ethers.getSigners())[i];
            const bid = ethers.utils.parseEther("0.25");
            const rand = ethers.utils.randomBytes(32);
            const commitment = await auction.createCommitment(bidder.address, bid, rand);
            
            // Push the commitments
            await( await auction.connect(bidder).commit(commitment)).wait();
            
            // Assert that the commitment has been received
            expect((await auction.commitments(commitment))).to.be.true;
        }

    });
});
