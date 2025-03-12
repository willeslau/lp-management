// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Callable is Ownable {
    address public caller;

    event CallerChanged(address indexed owner, address indexed caller);

    error NotCaller();

    modifier onlyCaller() {
        if (caller != msg.sender) {
            revert NotCaller();
        }
        _;
    }

    constructor(address _owner) Ownable() {}

    function setCaller(address _caller) public onlyOwner {
        caller = _caller;
        emit CallerChanged(msg.sender, _caller);
    }
}
