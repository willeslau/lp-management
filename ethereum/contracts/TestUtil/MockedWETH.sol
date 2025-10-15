// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WETH is ERC20 {
    uint8 private _decimals;

    constructor() ERC20("WETH", "WETH") {
        _mint(msg.sender, 1000000000 ether);
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint wad) public {
        _burn(msg.sender, wad);
    }
}
