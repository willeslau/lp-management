// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct SearchRange {
    uint256 swapInLow;
    uint256 swapInHigh;
    uint8 searchLoopNum;
}

struct CalculateParams {
    uint24 poolFee;

    address token0;
    address token1;

    uint256 amount0;
    uint256 amount1;

    uint160 sqrtP_Q96;
    uint160 sqrtPSlippage_Q96;

    uint160 R_Q96;
    uint160 REpslon_Q96;
}

/// @notice The utility contract to calculate how much tokens to swap for a liquidity pool
///         during rebalance for uniswap V3
interface ILiquiditySwapV3 {
    function calSwapToken0ForToken1(
        CalculateParams memory _params,
        SearchRange calldata _searchRange
    ) external returns(bool, uint256, uint256);

    function calSwapToken1ForToken0(
        CalculateParams memory _params,
        SearchRange calldata _searchRange
    ) external returns(bool, uint256, uint256);
}