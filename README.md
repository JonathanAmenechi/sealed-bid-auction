## Sealed bid auction contract for NFTs
![Github Actions](https://github.com/JonathanAmenechi/sealed-bid-auction/workflows/Tests/badge.svg)

Note: WIP

### Description

Implements a [First price sealed bid auction](https://en.wikipedia.org/wiki/First-price_sealed-bid_auction) contract and factory for a single ERC721 Asset. Inspired by the ENS RegistrarController.

Works using a commit-reveal scheme in which bidders commit hashed bids in the COMMIT phase and reveal their bids during the REVEAL phase.

The contract maintains custody of the Asset until the auction is Finalized, or Cancelled.
 

The Auction owner has the following privileges:
* Can start the auction with `startAuction`
* Can cancel the auction with `cancelAuction` if the auction hasn't started or the reserve price isn't met

This contract intends to be as trustless as possible:
* A new auction contract is deployed for each auction
* Auction parameters(commit duration, reveal duration, reserve price) are set on deployment and are immutable
* Anyone can advance the auction to the next phase once the auction has started


### Tests

`yarn test`

