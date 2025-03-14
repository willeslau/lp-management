// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";

import {TokenPair} from "./IUniswapV3TokenPairs.sol";

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

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
interface IUniswapV3PoolProxy {
    error InvalidCollectAmount();
    error PositionNotCleared();

    function mint(
        TokenPair calldata _tokenPair,
        MintParams calldata _mintParams
    ) external returns (LiquidityChangeOutput memory);

    function increaseLiquidity(
        TokenPair calldata tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (LiquidityChangeOutput memory);

    function decreaseLiquidity(
        IUniswapV3Pool _pool,
        uint128 _liquidityReduction,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external returns (LiquidityChangeOutput memory);

    function collect(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) external returns (uint256 amount0, uint256 amount1);

    function position(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    )
        external
        view
        returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1);
}
