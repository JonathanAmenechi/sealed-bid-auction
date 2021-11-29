// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import { SealedBidAuction } from "./SealedBidAuction.sol";

/**
* SealedBidAuctionFactory 
*/
contract SealedBidAuctionFactory is ERC721Holder {
    uint256 public constant MIN_DURATION = 1 hours;
    uint256 public constant MAX_DURATION = 1 weeks;

    uint256 public nonce = 0;

    // Events
    event AuctionDeployed(address indexed deployer, address indexed auction);

    function deployAuction(
        address bidToken, 
        address auctionedAsset, 
        uint256 auctionedAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice
    ) external {
        // Initial checks
        require(bidToken != address(0), "AuctionFactory::bidToken must not be zero address");
        require(auctionedAsset != address(0), "AuctionFactory::auctionedAsset must not be zero address");
        
        require(commitDuration >= MIN_DURATION, "AuctionFactory::commitDuration below min");
        require(revealDuration >= MIN_DURATION, "AuctionFactory::revealDuration below min");

        require(commitDuration <= MAX_DURATION, "AuctionFactory::commitDuration above max");
        require(revealDuration <= MAX_DURATION, "AuctionFactory::revealDuration above max");

        bytes32 salt = generateSalt(
                msg.sender, 
                bidToken, 
                auctionedAsset, 
                auctionedAssetID, 
                commitDuration, 
                revealDuration, 
                reservePrice,
                nonce
        );

        bytes memory creationCode = generateCreationCode(
            msg.sender, 
            bidToken, 
            auctionedAsset, 
            auctionedAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice
        );
        address auction =  Create2.deploy(0, salt, creationCode);
        nonce = nonce + 1;

        // Transfer auctionedAsset to the Auction
        IERC721(auctionedAsset).safeTransferFrom(msg.sender, auction, auctionedAssetID);
        
        emit AuctionDeployed(msg.sender, auction);
    }

    function generateCreationCode(
        address caller,
        address bidToken, 
        address auctionedAsset, 
        uint256 auctionedAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice
    ) internal pure returns(bytes memory) {
        return abi.encodePacked(
            type(SealedBidAuction).creationCode, 
            abi.encode(
                caller, 
                bidToken, 
                auctionedAsset, 
                auctionedAssetID, 
                commitDuration, 
                revealDuration, 
                reservePrice
            )
        );
    }

    function generateSalt(
        address caller,
        address bidToken, 
        address auctionedAsset, 
        uint256 auctionedAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice,
        uint256 nonce_
    ) internal pure returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                caller, 
                bidToken, 
                auctionedAsset, 
                auctionedAssetID, 
                commitDuration, 
                revealDuration, 
                reservePrice,
                nonce_
            )
        );
    }

    function computeAuctionAddress(
        address deployer,
        address caller,
        address bidToken, 
        address auctionedAsset, 
        uint256 auctionedAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice,
        uint256 nonce_
    ) public pure returns(address) {
        bytes32 salt = generateSalt(
            caller, 
            bidToken, 
            auctionedAsset, 
            auctionedAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice,
            nonce_
        );

        bytes memory creationCode = generateCreationCode(
            caller, 
            bidToken, 
            auctionedAsset, 
            auctionedAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice
        );

        return Create2.computeAddress(salt, keccak256(creationCode), deployer);

    }
}