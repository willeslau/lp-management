// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ISwapUtil} from "../SwapUtil.sol";
import {IUniswapV3TokenPairs} from "../interfaces/IUniswapV3TokenPairs.sol";

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 manager admin related functions
abstract contract UniswapV3LpManagerAdmin is OwnableUpgradeable {
    error InvalidActivation(bool activation);
    error NotAuthorized(address sender);
    error NotBalancer(address sender);
    error InvalidParam();

    /// @notice The protocol fee rate, base 1000 (e.g., 50 means 5%)
    uint16 protocolFeeRate;
    /// @notice The owner of liquidity. This address has the permission to close positions
    address public liquidityOwner;
    /// @notice The address that can rebalance the liquidity positions
    address public balancer;

    /// @dev A util contract that checks the list of supported uniswap v3 token pairs
    IUniswapV3TokenPairs public supportedTokenPairs;
    /// @notice A util library
    ISwapUtil public swapUtil;

    modifier onlyAddress(address _addr) {
        if (msg.sender != _addr) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    // function setParam(string calldata _what, bytes32 _value) public onlyOwner {
    //     activated = _activated;
    //     if (_what == "activated") { activated = _value != bytes32(0); }
    // }

    function setAddress(uint8 _what, address _address) public onlyOwner {
        if (_address == address(0)) {
            revert InvalidParam();
        }
        if (_what == 0) balancer = _address;
        else if (_what == 1) swapUtil = ISwapUtil(_address);
    }

    function setProtocolFeeRate(uint16 _newRate) external onlyOwner {
        if (_newRate > 1000) {
            revert InvalidParam();
        }
        protocolFeeRate = _newRate;
    }

    function _calculateProtocolFee(
        uint128 _amount
    ) internal view returns (uint128) {
        return (_amount * protocolFeeRate) / 1000;
    }
}
