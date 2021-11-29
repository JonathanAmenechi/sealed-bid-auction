## Sealed bid auction contract for NFTs
![Github Actions](https://github.com/JonathanAmenechi/sealed-bid-auction/workflows/Tests/badge.svg)

Note: WIP

### Description

Implements a sealed bid auction contract and factory for a single ERC721 Asset. Inspired by the ENS RegistrarController.

The contract maintains custody of the Asset until the auction is Finalized, or Cancelled.
 
It works using a commit-reveal scheme in which bidders commit hashed bids in the COMMIT phase and reveal their bids during the REVEAL phase. 

The Auction owner has the following privileges:
* 1) Can start the auction with `startCommitPhase`
* 2) Can cancel the auction with `cancelAuction` if the auction hasn't started or the reserve price isn't met

Apart from the above, this contract intends to be as trustless as possible:
* 1) New auction contract for each auction
* 2) Auction parameters(commit duration, reveal duration, reserve price) are set on deployment and are immutable
* 3) Anyone can advance the auction to the next phase once the auction has started

