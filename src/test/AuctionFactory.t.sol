// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";
import { AuctionFactory } from "../AuctionFactory.sol";

contract AuctionFactoryTest is DSTest {
    MockERC20 bidToken;
    MockERC721 auctionAsset;
    AuctionFactory factory;

    function setUp() public {
        bidToken = new MockERC20();
        auctionAsset = new MockERC721();
        factory = new AuctionFactory();

        // Mint test tokens
        bidToken.mint(address(this), 1e22);
        auctionAsset.mint(address(this), 0);

        // Approve the Auction asset on the factory
        auctionAsset.approve(address(factory), 0);
    }

    function testDeployAuction() public {
        // Deploy auction
        uint256 commitDuration = 3600;
        uint256 revealDuration = 3600;
        uint256 reservePrice = 0.1 ether;
        
        address expectedAuctionAddress = factory.computeAuctionAddress(
            address(factory),
            address(this), 
            address(bidToken), 
            address(auctionAsset), 
            0, 
            commitDuration, 
            revealDuration, 
            reservePrice, 
            factory.nonce()
        );

        address deployedAuction = factory.deployAuction(
            address(bidToken), 
            address(auctionAsset), 
            0, 
            commitDuration, 
            revealDuration, 
            reservePrice
        );

        assertEq(expectedAuctionAddress, deployedAuction);
    }
}
