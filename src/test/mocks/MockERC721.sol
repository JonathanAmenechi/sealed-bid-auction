// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { ERC721 } from "solmate/tokens/ERC721.sol";

contract MockERC721 is ERC721("TestNFT", "TNFT"){
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }

    function tokenURI(uint256) public pure virtual override returns (string memory) {}
}