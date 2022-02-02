// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "ds-test/test.sol";

import { Hevm } from "./utils/Hevm.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC721 } from "./mocks/MockERC721.sol";

import { Auction } from "../Auction.sol";
import { AuctionFactory } from "../AuctionFactory.sol";

// TODO: remove this 
import "./utils/console.sol";


contract AuctionTest is DSTest {
    Hevm constant hevm = Hevm(HEVM_ADDRESS);

    MockERC20 bidToken;
    MockERC721 auctionAsset;
    Auction auction;
    AuctionFactory factory;

    address constant bidderA = address(1);
    address constant bidderB = address(2);
    address constant bidderC = address(4);
    uint256 constant mintAmount = 1000 ether;
    
    function setUp() public {
        bidToken = new MockERC20();
        auctionAsset = new MockERC721();
        factory = new AuctionFactory();

        // Mint test tokens
        auctionAsset.mint(address(this), 0);
        bidToken.mint(bidderA, mintAmount);
        bidToken.mint(bidderB, mintAmount);
        bidToken.mint(bidderC, mintAmount);

        // Approve the Auction asset on the factory
        auctionAsset.approve(address(factory), 0);

        // Deploy new auction
        address auctionAddress = factory.deployAuction(
            address(bidToken), 
            address(auctionAsset), 
            0, 
            1 hours, 
            1 hours, 
            0.01 ether
        );
        auction = Auction(auctionAddress);

        // Approve the bid token on the Auction for the bidders
        hevm.prank(bidderA);
        bidToken.approve(auctionAddress, type(uint256).max);
        
        hevm.prank(bidderB);
        bidToken.approve(auctionAddress, type(uint256).max);
        
        hevm.prank(bidderC);
        bidToken.approve(auctionAddress, type(uint256).max);
    }

    function testFailStartAuction() public {
        hevm.prank(address(100));
        auction.startAuction();
    }

    function testStartAuction() public {
        // The Auction is inactive before starting
        assertEq(uint256(auction.currentPhase()), 0);

        // Start the auction
        auction.startAuction();
        // Ensure that the auction is in the Commit Phase
        assertEq(uint256(auction.currentPhase()), 1);
    }

    function testFailCommit() public {
        // Fails as the auction has not been started
        _commit(bidderA, 1 ether, bytes32("aDc"));
    }

    function testCommit() public {
        // start the auction
        auction.startAuction();
        assertEq(uint256(auction.currentPhase()), 1);
        
        // Create a commitment to bid on the auction
        bytes32 commitment = _commit(bidderA, 1 ether, bytes32("aDc"));
        assertTrue(auction.commitments(commitment));
    }

    function testFailStartRevealPhase() public {
        // start the auction
        auction.startAuction();
        
        // Fails since the REVEAL phase has not started
        auction.startRevealPhase();
    }

    function testStartRevealPhase() public {
        // start the auction
        auction.startAuction();
        assertEq(uint256(auction.currentPhase()), 1);
    
        // fast forward to after the COMMIT phase is over
        hevm.warp(1.5 hours);

        // start the REVEAL phase
        auction.startRevealPhase();
        assertEq(uint256(auction.currentPhase()), 2);
    }

    function testReveal() public {
        // start the auction
        auction.startAuction();
        
        // COMMMIT phase
        // place commit bids
        _commit(bidderA, 1 ether, bytes32("aDc"));
        _commit(bidderB, 1.5 ether, bytes32("2ho"));
        _commit(bidderC, 0.1 ether, bytes32("wolo"));

        // fast forward to after the COMMIT phase is over
        hevm.warp(1.5 hours);

        // start the REVEAL phase
        auction.startRevealPhase();
        assertEq(uint256(auction.currentPhase()), 2);

        // REVEAL phase
        // Reveal the first bid
        _reveal(bidderA, 1 ether, bytes32("aDc"));
        // Ensure the highest bid and bidder has been updated
        assertEq(auction.highestBid(), 1 ether);
        assertEq(auction.highestBidder(), bidderA); 
        
        // Ensure bid tokens have been transferred to the Auction from bidderA
        assertEq(bidToken.balanceOf(address(auction)), 1 ether);
        assertEq(bidToken.balanceOf(bidderA), mintAmount - 1 ether);

        // Reveal the second bid
        _reveal(bidderB, 1.5 ether, bytes32("2ho"));
        assertEq(auction.highestBid(), 1.5 ether);
        assertEq(auction.highestBidder(), bidderB);

        // Ensure bid tokens have been transferred to the Auction from bidderB
        // And that bidderA's tokens have been refunded
        assertEq(bidToken.balanceOf(address(auction)), 1.5 ether);
        assertEq(bidToken.balanceOf(bidderB), mintAmount - 1.5 ether);
        assertEq(bidToken.balanceOf(bidderA), mintAmount);

        // Reveal the third bid
        _reveal(bidderC, 0.1 ether, bytes32("wolo"));

        // Ensure that no tokens have been transferred as bidderC's bid is non-competitive
        assertEq(bidToken.balanceOf(bidderA), mintAmount);
    }

    function testFailFinalize() public {
        // start the auction
        auction.startAuction();
        _commit(bidderA, 1 ether, bytes32("aDc"));
        
        hevm.warp(1.5 hours);
        auction.startRevealPhase();

        _reveal(bidderA, 1 ether, bytes32("aDc"));

        auction.finalize();
    }

    function testFinalize() public {
        // start the auction
        auction.startAuction();
        _commit(bidderA, 1 ether, bytes32("aDc"));
        // fast forward to after the COMMIT phase is over
        hevm.warp(1.5 hours);
        auction.startRevealPhase();

        _reveal(bidderA, 1 ether, bytes32("aDc"));

        // fast forward to after the REVEAL phase
        hevm.warp(3 hours);

        // Finalize the auction, sending bid tokens to the auction deployer 
        // and the auction asset to the winning bidder
        auction.finalize();

        assertEq(uint256(auction.currentPhase()), 3);
        
        assertEq(auctionAsset.ownerOf(0), bidderA);
        assertEq(bidToken.balanceOf(auction.owner()), 1 ether);
    }

    function _commit(address bidder, uint256 bidAmount, bytes32 secret) internal returns (bytes32 commitment) {
        hevm.startPrank(bidder);
        commitment = auction.createCommitment(bidder, bidAmount, secret);
        auction.commit(commitment);
        hevm.stopPrank();
    }

    function _reveal(address bidder, uint256 bidAmount, bytes32 secret) internal {
        hevm.startPrank(bidder);
        auction.reveal(bidAmount, secret);
        hevm.stopPrank();
    }
}
