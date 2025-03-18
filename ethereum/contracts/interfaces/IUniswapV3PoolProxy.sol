// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct MintParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
}

struct LiquidityChangeOutput {
    uint256 amount0;
    uint256 amount1;
}
