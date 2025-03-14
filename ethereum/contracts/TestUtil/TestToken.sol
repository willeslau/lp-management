//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        address _recipient,
        uint256 _amount
    ) ERC20(name_, symbol_) {
        _mint(_recipient, _amount);
    }
}
