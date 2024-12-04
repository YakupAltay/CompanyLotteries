// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    bool public failTransfer = false;

    constructor() ERC20("MockERC20", "Mock") {}

    // Add mint function for testing
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Set the failTransfer flag
    function setFailTransfer(bool _fail) external {
        failTransfer = _fail;
    }

    // Override the transfer function to simulate failure
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (failTransfer) {
            revert("Refund transfer failed!");
        }
        return super.transfer(recipient, amount);
    }
}
