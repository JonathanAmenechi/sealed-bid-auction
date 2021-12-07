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
    await( await test721.mint(deployer.address, 1)).wait();

    // Deploy factory
    const factory: SealedBidAuctionFactory = <SealedBidAuctionFactory>await deploy("SealedBidAuctionFactory", 
    {
        from: deployer.address,
        args: []
    });

    // approve test 721 on factory
    await(await test721.approve(factory.address, 1)).wait();

    return {
        deployer,
        bidToken,
        test721,
        factory
    };
});



describe("Sealed Bid Auction Factory tests", function () {
    let deployer: SignerWithAddress;
    let bidToken: TestToken;
    let test721: Test721;
    let factory: SealedBidAuctionFactory;

    beforeEach(async function () {
        const set = await setup();
        deployer = set.deployer;
        bidToken = set.bidToken;
        test721 = set.test721;
        factory = set.factory;
    });

    it("should correctly deploy the Auction from the factory", async function () {
        const bidTokenAddress = bidToken.address;
        const auctionedAsset = test721.address;
        const auctionedAssetID = 1;
        const commitDuration = 3600; // 1 hour
        const revealDuration = 3600; // 1 hour
        const reservePrice = 0;
        const nonce = await factory.nonce();
        
        const expectedAuctionAddress = await factory.computeAuctionAddress(
            factory.address,
            deployer.address, 
            bidTokenAddress, 
            auctionedAsset, 
            auctionedAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice, 
            nonce
        );

        // Check the deployed auction contract
        await expect(
            factory.connect(deployer)
                .deployAuction(
                    bidTokenAddress, 
                    auctionedAsset, 
                    auctionedAssetID, 
                    commitDuration, 
                    revealDuration, 
                    reservePrice
                )
        )
        .to.emit(factory, "AuctionDeployed")
        .withArgs(deployer.address, expectedAuctionAddress);

        const auction: SealedBidAuction = <SealedBidAuction>await ethers.getContractAt("SealedBidAuction", expectedAuctionAddress);

        // Check that the Auction contract now has custody of the Test721
        const test721Owner = await test721.ownerOf(1);
        expect(auction.address).to.eq(test721Owner);
    });
});
