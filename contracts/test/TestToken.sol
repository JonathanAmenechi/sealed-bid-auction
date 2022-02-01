// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20("TestToken", "TST") {
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
