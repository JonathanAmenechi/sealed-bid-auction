// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { ERC721Holder } from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import { SealedBidAuction } from "./SealedBidAuction.sol";


/// @title SealedBidAuctionFactory
/// @notice Creates new sealed bid auctions
contract SealedBidAuctionFactory is ERC721Holder {
    uint256 public immutable minDuration = 1 hours;
    uint256 public immutable maxDuration = 1 weeks;
    uint256 public nonce = 0;

    event AuctionDeployed(address indexed deployer, address indexed auction);

    /// @notice Deploys a new auction
    /// @param bidToken       - Token used to bid on the auction
    /// @param auctionAsset   - Asset being auctioned off
    /// @param auctionAssetID - ERC721 tokenID of the Asset being auctioned off
    /// @param commitDuration - Length of the COMMIT phase
    /// @param revealDuration - Length of the REVEAL phase
    /// @param reservePrice   - Price at which an auction c
    function deployAuction(
        address bidToken, 
        address auctionAsset, 
        uint256 auctionAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice
    ) external {
        require(commitDuration >= minDuration, "AuctionFactory::commitDuration below min");
        require(revealDuration >= minDuration, "AuctionFactory::revealDuration below min");

        require(commitDuration <= maxDuration, "AuctionFactory::commitDuration above max");
        require(revealDuration <= maxDuration, "AuctionFactory::revealDuration above max");

        bytes32 salt = generateSalt(
                msg.sender, 
                bidToken, 
                auctionAsset, 
                auctionAssetID, 
                commitDuration, 
                revealDuration, 
                reservePrice,
                nonce
        );
        
        bytes memory creationCode = generateCreationCode(
            msg.sender, 
            bidToken, 
            auctionAsset, 
            auctionAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice
        );
        address auction =  Create2.deploy(0, salt, creationCode);
        
        unchecked {
            nonce += 1;
        }

        // Transfer auctionAsset to the Auction
        IERC721(auctionAsset).safeTransferFrom(msg.sender, auction, auctionAssetID);
        emit AuctionDeployed(msg.sender, auction);
    }

    function generateCreationCode(
        address caller,
        address bidToken, 
        address auctionAsset, 
        uint256 auctionAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice
    ) internal pure returns(bytes memory) {
        return abi.encodePacked(
            type(SealedBidAuction).creationCode, 
            abi.encode(
                caller, 
                bidToken, 
                auctionAsset, 
                auctionAssetID, 
                commitDuration, 
                revealDuration, 
                reservePrice
            )
        );
    }

    function generateSalt(
        address caller,
        address bidToken, 
        address auctionAsset, 
        uint256 auctionAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice,
        uint256 nonce_
    ) internal pure returns(bytes32) {
        return keccak256(
            abi.encodePacked(
                caller, 
                bidToken, 
                auctionAsset, 
                auctionAssetID, 
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
        address auctionAsset, 
        uint256 auctionAssetID, 
        uint256 commitDuration, 
        uint256 revealDuration, 
        uint256 reservePrice,
        uint256 nonce_
    ) public pure returns(address) {
        bytes32 salt = generateSalt(
            caller, 
            bidToken, 
            auctionAsset, 
            auctionAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice,
            nonce_
        );

        bytes memory creationCode = generateCreationCode(
            caller, 
            bidToken, 
            auctionAsset, 
            auctionAssetID, 
            commitDuration, 
            revealDuration, 
            reservePrice
        );
        return Create2.computeAddress(salt, keccak256(creationCode), deployer);
    }
}