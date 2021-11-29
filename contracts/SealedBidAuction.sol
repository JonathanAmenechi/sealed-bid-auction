// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";


/**
 * @title Sealed Bid Auction
 * @notice Smart contract that allows a user to start a first price sealed bid auction(aka blind auction) 
 * for a single ERC721 asset. Inspired by the ENS RegistrarController.
 *
 * The contract maintains custody of the Asset until the auction is Finalized, or Cancelled.
 * 
 * It works using a commit-reveal scheme in which bidders commit hashed bids in the COMMIT phase
 * and reveal their bids during the REVEAL phase. 
 * 
 * The Auction owner has the following privileges:
 * 1) Can start the auction with `startCommitPhase`
 * 2) Can cancel the auction and withdraw the asset if the auction hasn't started or the reserve price isn't met
 *
 * Apart from the above, this contract intends to be as trustless as possible:
 * 1) Auction parameters(commit duration, reveal duration, reserve price) are set on deployment and are immutable
 * 2) Anyone can advance the auction to the next phase once the auction has started
 */

contract SealedBidAuction is ERC721Holder, Ownable {

    // Structs
    struct Bid {
        address bidder;
        uint256 bidAmount; 
    }

    enum AuctionPhase {
        INACTIVE, 
        COMMIT,
        REVEAL,
        FINALIZED,
        RESERVE_NOT_MET,
        CANCELED
    }

    // Events
    // TODO: could use PhaseChanged as a general event, but not very useful to log readers
    // event PhaseChanged(address indexed caller, AuctionPhase oldPhase, AuctionPhase newPhase);
    event CommitPhaseStarted(address indexed caller);
    event RevealPhaseStarted(address indexed caller);
    event Finalized(address indexed caller, address indexed winner, uint256 indexed winningBid);
    event Cancelled(address indexed caller);

    // Immutable Auction Parameters
    IERC20 public immutable bidToken;

    address public immutable asset;
    uint256 public immutable assetID;

    uint256 public immutable commitPhaseDuration;
    uint256 public immutable revealPhaseDuration;
    uint256 public immutable reservePrice;

    mapping(bytes32 => bool) public commitments;

    Bid public highestBid;

    uint256 public commitPhaseEnd;
    uint256 public revealPhaseEnd;

    // All auctions start inactive
    AuctionPhase public currentPhase = AuctionPhase.INACTIVE;

    constructor(
        address admin,
        address bidTokenAddress, 
        address asset_, 
        uint256 assetID_,
        uint256 commitPhaseDuration_, 
        uint256 revealPhaseDuration_, 
        uint256 reservePrice_
    ) ERC721Holder() Ownable() {
        bidToken = IERC20(bidTokenAddress);
        asset = asset_;
        assetID = assetID_;
        commitPhaseDuration = commitPhaseDuration_;
        revealPhaseDuration = revealPhaseDuration_;
        reservePrice = reservePrice_;
        transferOwnership(admin);
    }

    /**
    * Starts the commit phase of an auction
    * Only the Auction owner can start the commit phase 
    */
    function startCommitPhase() public onlyOwner {
        require(currentPhase == AuctionPhase.INACTIVE, "Auction::auction already in progress");
        commitPhaseEnd = block.timestamp + commitPhaseDuration;
        currentPhase = AuctionPhase.COMMIT;
        emit CommitPhaseStarted(msg.sender);
    }

    /**
    * Starts the reveal phase of the auction. Can be called by anyone
    */
    function startRevealPhase() public {
        require(currentPhase == AuctionPhase.COMMIT, "Auction::must be in commit phase");
        require(block.timestamp >= commitPhaseEnd, "Auction::commit phase has not ended");
        
        revealPhaseEnd = block.timestamp + revealPhaseDuration;
        currentPhase = AuctionPhase.REVEAL;
        emit RevealPhaseStarted(msg.sender);
    }

    /**
    * Creates a commitment to bid at a certain price
    */
    function commit(bytes32 commitment) public {
        require(currentPhase == AuctionPhase.COMMIT, "Auction::must be in commit phase");
        require(block.timestamp <= commitPhaseEnd, "Auction::commit phase has ended");
        commitments[commitment] = true;
    } 

    function reveal(uint256 bid, bytes32 secret) public {
        // check in reveal phase
        // check in reveal period
        // create commitment
        // check commitment exists
        // check >= reserve price
        // check > current top bid
        // if strictly > top bid, 
        //     check token approval on caller with address(this) as spender and token balance on caller
        //     safe transfer from token to address(this)
    }

    /**
    * Ends the auction and transfers the asset to the highest revealed bid.
    * If the reserve price isn't met, the auction is set to RESERVE_NOT_MET.
    * Can be called by anyone
    */
    function finalize() public {
        //Checks
        // Check in REVEAL phase
        // check after reveal period
        // if highest bid: transfer asset to highest bidder, transfer highest bid tokens to owner
        // set AuctionPhase to Finalized
        // reserve price not reached
        // set AuctionPhase to RESERVE_NOT_MET
    }

    /**
    * Cancels the auction and returns the asset to the auction owner
    * Can only be called if an auction is in the INACTIVE or RESERVE_NOT_MET phases
    */
    function cancelAuction() public onlyOwner {
        require(
            currentPhase == AuctionPhase.INACTIVE || currentPhase == AuctionPhase.RESERVE_NOT_MET, 
            "Auction::auction in progress"
        );
        
        emit Cancelled(msg.sender);
        currentPhase = AuctionPhase.CANCELED;
        
        // transfer ERC721 to owner
        IERC721(asset).safeTransferFrom(address(this), owner(), assetID);
    }
}