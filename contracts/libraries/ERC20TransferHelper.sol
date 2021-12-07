// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


library ERC20TransferHelper {
    
    function safeTransferFrom(address asset, address from, address to, uint256 amount) internal {
        require(
            IERC20(asset).transferFrom(from, to, amount),
            "TransferHelper::STF"
        );
    }
}