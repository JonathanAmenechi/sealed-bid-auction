// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


library ERC20TransferHelper {
    
    function safeTransferFrom(address asset, address from, address to, uint256 amount) public {
        require(
            IERC20(asset).transferFrom(from, to, amount),
            "ERC20 Safe transfer from failed"
        );
    }
}