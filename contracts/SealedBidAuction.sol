// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { TransferHelper } from "./libraries/TransferHelper.sol";


/// @title Sealed Bid Auction
/// @notice Smart contract that allows a user to start a first price sealed bid auction(aka blind auction) 
/// for a single ERC721 asset. Inspired by the ENS RegistrarController.
/// The contract maintains custody of the Asset until the auction is Finalized, or Cancelled.
///
contract SealedBidAuction is ERC721Holder, Ownable {

    enum AuctionPhase {
        INACTIVE, 
        COMMIT,
        REVEAL,
        FINALIZED,
        RESERVE_NOT_MET,
        CANCELED
    }

    event NewHighestBid(address highestBidder, uint256 highestBid, address oldHighestBidder, uint256 oldHighestBid);
    event Finalized(address indexed caller, address indexed winner, uint256 indexed winningBid);
    event Cancelled(address indexed caller);

    /// @dev ERC20 token address used to bid on this auction
    address public immutable bidToken;
    
    /// @dev ERC721 token address that is being auctioned
    address public immutable auctionAsset;
    
    /// @dev ERC721 token ID that is being auctioned
    uint256 public immutable auctionAssetID;
    
    /// @dev The duration of the commit phase
    uint256 public immutable commitPhaseDuration;
    
    /// @dev The duration of the reveal phase
    uint256 public immutable revealPhaseDuration;

    /// @dev The minimum price that the auctionAsset can be sold for.
    /// Can be 0.
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
    ) ERC721Holder() Ownable() {
        bidToken = bidToken_;
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
    function reveal(uint256 bid, bytes32 secret) public {
        require(currentPhase == AuctionPhase.REVEAL, "Auction::must be in reveal phase");
        require(block.timestamp <= revealPhaseEnd, "Auction::reveal phase has ended");

        bytes32 commitment = createCommitment(msg.sender, bid, secret);

        require(commitments[commitment], "Auction::nonexistent commitment");
        require(bid >= reservePrice, "Auction::unmet reserve price");

        address oldHighestBidder;
        uint256 oldHighestBid;

        // If first bid, update the highest bid and bidder
        if(highestBidder == address(0)) {
            oldHighestBidder = address(0);
            oldHighestBid = 0;
            
            // Transfer bid token from the bidder to the auction contract 
            TransferHelper.safeTransferFrom(bidToken, msg.sender, address(this), bid);

            // Update highest bidder and highest bid
            updateHighestBid(msg.sender, bid);

            emit NewHighestBid(msg.sender, bid, oldHighestBidder, oldHighestBid);
            return;
        }
        
        // If current bid strictly > highest bid 
        if (bid > highestBid) {
            oldHighestBidder = highestBidder;
            oldHighestBid = highestBid;
            
            // Refund previous highest bidder
            refundHighestBidder();
            
            // Transfer bid token to the auction contract 
            TransferHelper.safeTransferFrom(bidToken, msg.sender, address(this), bid);

            // Update highest bidder and highest bid
            updateHighestBid(msg.sender, bid);

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
    function finalize() public {
        require(currentPhase == AuctionPhase.REVEAL, "Auction::must be in reveal phase");
        require(block.timestamp > revealPhaseEnd, "Auction::reveal phase has not ended");
        
        if(highestBid >= reservePrice) {
            // Transfer auctionAsset to the highest bidder
            IERC721(auctionAsset).safeTransferFrom(address(this), highestBidder, auctionAssetID);
            
            // transfer bid Tokens to the Auction owner
            TransferHelper.safeTransfer(bidToken, owner(), highestBid);

            currentPhase = AuctionPhase.FINALIZED;
            
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
        IERC721(auctionAsset).safeTransferFrom(address(this), owner(), auctionAssetID);
    }

    function updateHighestBid(address bidder, uint256 bidAmount) internal {
        highestBidder = bidder;
        highestBid = bidAmount;
    }

    function refundHighestBidder() internal {
        TransferHelper.safeTransfer(bidToken, highestBidder, highestBid);
    }
}