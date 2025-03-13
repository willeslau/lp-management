// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct SearchRange {
    int256 swapInLow;
    int256 swapInHigh;
    uint8 searchLoopNum;
}

/// @notice The utility contract to calculate how much tokens to swap for a liquidity pool
///         during rebalance for uniswap V3
interface ILiquiditySwapV3 {
    function swapWithSearch1For0(
        address _pool,
        uint160 _sqrtPriceLimitX96,
        SearchRange calldata _searchRange,
        bytes calldata _preSwapCalldata
    ) external;

    function swapWithSearch0For1(
        address _pool,
        uint160 _sqrtPriceLimitX96,
        SearchRange calldata _searchRange,
        bytes calldata _preSwapCalldata
    ) external ;
}
