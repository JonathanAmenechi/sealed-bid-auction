// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { Ownable } from "./lib/Ownable.sol";

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "solmate/utils/ReentrancyGuard.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC721, ERC721TokenReceiver } from "solmate/tokens/ERC721.sol";


/// @title Auction
/// @notice Smart contract that allows a user to start a first price sealed bid auction(aka blind auction) 
/// for a single ERC721 asset. Inspired by the ENS RegistrarController.
/// The contract maintains custody of the Asset until the auction is Finalized, or Cancelled.
contract Auction is ERC721TokenReceiver, ReentrancyGuard, Ownable {

    enum AuctionPhase {
        INACTIVE, 
        COMMIT,
        REVEAL,
        FINALIZED,
        RESERVE_NOT_MET,
        CANCELED
    }

    /// Events
    event NewHighestBid(address highestBidder, uint256 highestBid, address oldHighestBidder, uint256 oldHighestBid);
    event Finalized(address indexed caller, address indexed winner, uint256 indexed winningBid);
    event Cancelled(address indexed caller);

    /// @dev ERC20 token address used to bid on this auction
    ERC20 public immutable bidToken;
    
    /// @dev ERC721 token address that is being auctioned
    address public immutable auctionAsset;
    
    /// @dev ERC721 token ID that is being auctioned
    uint256 public immutable auctionAssetID;
    
    /// @dev The duration of the commit phase
    uint256 public immutable commitPhaseDuration;
    
    /// @dev The duration of the reveal phase
    uint256 public immutable revealPhaseDuration;

    /// @dev The minimum price that the auctionAsset can be sold for.
    /// Can be set to 0.
    uint256 public immutable reservePrice;

    address public highestBidder = address(0);
    uint256 public highestBid = 0;
    uint256 public commitPhaseEnd;
    uint256 public revealPhaseEnd;

    /// @dev starting auction phase is always INACTIVE
    AuctionPhase public currentPhase = AuctionPhase.INACTIVE;

    /// @dev Mapping of received commitments
    mapping(bytes32 => bool) public commitments;

    constructor(
        address admin,
        address bidToken_, 
        address asset_, 
        uint256 assetID_,
        uint256 commitPhaseDuration_, 
        uint256 revealPhaseDuration_, 
        uint256 reservePrice_
    ) ERC721TokenReceiver() Ownable() {
        bidToken = ERC20(bidToken_);
        auctionAsset = asset_;
        auctionAssetID = assetID_;
        commitPhaseDuration = commitPhaseDuration_;
        revealPhaseDuration = revealPhaseDuration_;
        reservePrice = reservePrice_;
        transferOwnership(admin);
    }

    /// @notice Starts an auction
    /// @notice Moves the auction to the COMMIT phase
    /// @notice Only the Auction owner can start the auction
    function startAuction() public onlyOwner {
        require(currentPhase == AuctionPhase.INACTIVE, "Auction::auction already in progress");
        commitPhaseEnd = block.timestamp + commitPhaseDuration;
        currentPhase = AuctionPhase.COMMIT;
    }

    /// @notice Starts the reveal phase of the auction
    function startRevealPhase() public {
        require(currentPhase == AuctionPhase.COMMIT, "Auction::must be in commit phase");
        require(block.timestamp > commitPhaseEnd, "Auction::commit phase has not ended");
        
        revealPhaseEnd = block.timestamp + revealPhaseDuration;
        currentPhase = AuctionPhase.REVEAL;
    }

    /// @notice Creates a commitment to bid at a certain price
    /// @param commitment - A hash of the bidder, bidAmount and a secret
    function commit(bytes32 commitment) public {
        require(currentPhase == AuctionPhase.COMMIT, "Auction::must be in commit phase");
        require(block.timestamp <= commitPhaseEnd, "Auction::commit phase has ended");
        commitments[commitment] = true;
    } 

    /// @notice Reveals a previously placed bid
    /// @param bid    - The Bid amount
    /// @param secret - The Secret
    function reveal(uint256 bid, bytes32 secret) public nonReentrant {
        require(currentPhase == AuctionPhase.REVEAL, "Auction::must be in reveal phase");
        require(block.timestamp <= revealPhaseEnd, "Auction::reveal phase has ended");

        bytes32 commitment = createCommitment(msg.sender, bid, secret);

        require(commitments[commitment], "Auction::nonexistent commitment");
        require(bid >= reservePrice, "Auction::unmet reserve price");

        // First bid
        if(highestBidder == address(0)) {
            // Update highest bidder and highest bid
            highestBidder = msg.sender;
            highestBid = bid;

            // Transfer bid token from the bidder to the auction contract 
            SafeTransferLib.safeTransferFrom(bidToken, msg.sender, address(this), bid);            
            
            // Clear the commitment
            delete commitments[commitment];

            emit NewHighestBid(msg.sender, bid, address(0), 0);
            return;
        }
        
        // If current bid strictly > highest bid 
        if (bid > highestBid) {
            address oldHighestBidder = highestBidder;
            uint256 oldHighestBid = highestBid;
            
            // Refund previous highest bidder
            SafeTransferLib.safeTransfer(bidToken, highestBidder, highestBid);
            
            // Transfer bid token to the auction contract 
            SafeTransferLib.safeTransferFrom(bidToken, msg.sender, address(this), bid);

            // Update highest bidder and highest bid
            highestBidder = msg.sender;
            highestBid = bid;

            // Clear the commitment
            delete commitments[commitment];

            emit NewHighestBid(msg.sender, bid, oldHighestBidder, oldHighestBid);
            return;
        }
    }

    /// @notice Creates a commitment hash
    /// @param bidder - The address placing the bid
    /// @param bid    - The bid to be placed
    /// @param secret - The secret
    function createCommitment(address bidder, uint256 bid, bytes32 secret) public pure returns (bytes32 commitment) {
        commitment= keccak256(abi.encodePacked(bidder, bid, secret));
    }

    /// @notice Ends the auction and transfers the asset to the winner of the auction
    /// @notice If the reserve price isn't met, the auction is set to RESERVE_NOT_MET
    function finalizeAuction() public nonReentrant {
        require(currentPhase == AuctionPhase.REVEAL, "Auction::must be in reveal phase");
        require(block.timestamp > revealPhaseEnd, "Auction::reveal phase has not ended");
        
        if(highestBid >= reservePrice) {
            currentPhase = AuctionPhase.FINALIZED;
            
            // Transfer auctionAsset to the highest bidder
            ERC721(auctionAsset).safeTransferFrom(address(this), highestBidder, auctionAssetID);
            
            // transfer the auction proceeds to the Auction owner
            SafeTransferLib.safeTransfer(bidToken, owner(), highestBid);

            emit Finalized(msg.sender, highestBidder, highestBid);
        } else {

            // Reserve price not met
            currentPhase = AuctionPhase.RESERVE_NOT_MET;
        }
    }

    /// @notice Cancels the auction and returns the asset to the auction owner
    /// @notice Can only be called if an auction is in the INACTIVE or RESERVE_NOT_MET phases
    function cancelAuction() public onlyOwner {
        require(
            currentPhase == AuctionPhase.INACTIVE 
            ||
            currentPhase == AuctionPhase.RESERVE_NOT_MET, 
            "Auction::auction cannot be cancelled"
        );
        
        emit Cancelled(msg.sender);
        currentPhase = AuctionPhase.CANCELED;
        
        // transfer auctionAsset to owner
        ERC721(auctionAsset).safeTransferFrom(address(this), owner(), auctionAssetID);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}