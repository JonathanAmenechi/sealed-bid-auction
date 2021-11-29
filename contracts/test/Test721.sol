// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";


contract Test721 is ERC721("TestNFT", "TNFT") {

    function mint(address to, uint256 tokenID) public {
        _mint(to, tokenID);
    }
}