// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";

import {UniswapV3PositionLib, Position, MintParams} from "../libraries/UniswapV3PositionLib.sol";

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
interface IUniswapV3LpManager {
    error InvalidPositionId(uint256 positionId);
    error InsufficientLiquidity(uint256 positionId);
    error PriceSlippageCheck();
    error InvalidCollectAmount();
    error PositionNotCleared();

    /// @notice Emitted when liquidity is increased for a position NFT
    /// @dev Also emitted when a position is minted
    /// @param positionId The ID of the position for which liquidity was increased
    /// @param liquidity The amount by which liquidity for the NFT position was increased
    /// @param amount0 The amount of position0 that was paid for the increase in liquidity
    /// @param amount1 The amount of position1 that was paid for the increase in liquidity
    event IncreaseLiquidity(
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when liquidity is decreased for a position NFT
    /// @param positionId The ID of the position for which liquidity was decreased
    /// @param liquidity The amount by which liquidity for the NFT position was decreased
    /// @param amount0 The amount of position0 that was accounted for the decrease in liquidity
    /// @param amount1 The amount of position1 that was accounted for the decrease in liquidity
    event DecreaseLiquidity(
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when positions are collected for a position NFT
    /// @dev The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior
    /// @param positionId The ID of the position for which underlying positions were collected
    /// @param recipient The address of the account that received the collected positions
    /// @param amount0 The amount of position0 owed to the position that was collected
    /// @param amount1 The amount of position1 owed to the position that was collected
    event Collect(
        uint256 indexed positionId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when a new position is created
    /// @param positionId The ID of the position for which position was created
    /// @param liquidity The amount of liquidity provided for the position
    /// @param amount0 The amount of position0 used to create the position
    /// @param amount1 The amount of position1 used to create the position
    event PositionCreated(
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    function updatePosition(uint256 oldPositionId, uint256 newPositionId) external;

    /// @dev Gets pool instance and pool key for a position
    function getPoolInfo(
        uint256 positionId
    )
        external
        view
        returns (
            IUniswapV3Pool pool,
            PoolAddress.PoolKey memory poolKey,
            uint256 position0,
            uint256 position1
        );

    function mint(
        address position0,
        address position1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint16 maxMintSlippageRate
    )
        external
        returns (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    function increaseLiquidity(
        uint256 positionId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(
        uint256 positionId,
        uint16 percentage,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(
        uint256 positionId,
        address recipient,
        uint128 amount0Max,
        uint128 amount1Max
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            PoolAddress.PoolKey memory poolKey
        );
}
