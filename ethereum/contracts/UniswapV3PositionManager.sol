// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";

import {LibPercentageMath} from "./RateMath.sol";
import {UniswapV3PositionLib, Position, MintParams} from "./libraries/UniswapV3PositionLib.sol";
import "./interfaces/IUniswapV3LpManager.sol";
import "./UniswapV3LiquidityManagement.sol";
import "./Callable.sol";

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
/// copy from https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/NonfungiblePositionManager.sol
contract UniswapV3PositionManager is
    UniswapV3LiquidityManagement,
    IUniswapV3LpManager,
    Callable
{
    /// @dev IDs of pools assigned by this contract
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The token ID position data
    mapping(uint256 => Position) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    uint80 private _nextPoolId = 1;

    constructor(
        address _factory,
        address _WETH9
    ) PeripheryImmutableState(_factory, _WETH9) Callable(msg.sender) {}

    /// @dev Caches a pool key
    function cachePoolKey(
        address pool,
        PoolAddress.PoolKey memory poolKey
    ) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }

    function updatePosition(
        uint256 oldPositionId,
        uint256 newPositionId
    ) external onlyCaller {
        _nextId--;
        _positions[oldPositionId] = _positions[newPositionId];
        delete _positions[newPositionId];
    }

    function burn(uint256 positionId) external onlyCaller {
        Position storage position = _positions[positionId];
        if (
            position.liquidity != 0 ||
            position.tokensOwed0 != 0 ||
            position.tokensOwed1 != 0
        ) revert PositionNotCleared();
        delete _positions[positionId];
    }

    function getPoolInfo(
        uint256 positionId
    )
        external
        view
        override
        returns (
            PoolAddress.PoolKey memory poolKey,
            uint256 amount0,
            uint256 amount1
        )
    {
        Position storage position = _positions[positionId];
        if (position.poolId == 0) {
            revert InvalidPositionId(positionId);
        }

        if (position.liquidity == 0) {
            revert InsufficientLiquidity(positionId);
        }
        amount0 = position.tokensOwed0;
        amount1 = position.tokensOwed1;
        poolKey = _poolIdToPoolKey[position.poolId];
    }

    function mint(
        TokenPair calldata tokenPair,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint16 maxMintSlippageRate
    )
        external
        override
        onlyCaller
        returns (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        MintParams memory params = MintParams({
            tokenPair: tokenPair,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired
        });

        (uint256 amount0Min, uint256 amount1Min) = UniswapV3PositionLib
            .calculateMinAmounts(
                params.amount0Desired,
                params.amount1Desired,
                maxMintSlippageRate
            );
        AddLiquidityParams memory addParams = AddLiquidityParams({
            tokenPair: params.tokenPair,
            recipient: address(this),
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            amount0Desired: params.amount0Desired,
            amount1Desired: params.amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min
        });

        positionId = _nextId++;
        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(addParams);

        bytes32 positionKey = PositionKey.compute(
            address(this),
            params.tickLower,
            params.tickUpper
        );
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = pool.positions(positionKey);

        uint80 poolId = cachePoolKey(
            address(pool),
            PoolAddress.PoolKey({
                token0: params.tokenPair.token0,
                token1: params.tokenPair.token1,
                fee: params.tokenPair.poolFee
            })
        );

        UniswapV3PositionLib.createPosition(
            _positions,
            positionId,
            poolId,
            params.tickLower,
            params.tickUpper,
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128
        );

        emit PositionCreated(positionId, liquidity, amount0, amount1);
    }

    function increaseLiquidity(
        TokenPair calldata tokenPair,
        uint256 positionId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        onlyCaller
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        Position storage position = _positions[positionId];

        (liquidity, amount0, amount1, ) = addLiquidity(
            AddLiquidityParams({
                tokenPair: tokenPair,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this)
            })
        );

        UniswapV3PositionLib.updatePositionFeeGrowth(
            position,
            tokenPair.pool,
            position.liquidity
        );
        position.liquidity += liquidity;

        emit IncreaseLiquidity(positionId, liquidity, amount0, amount1);
    }

    function decreaseLiquidity(
        address pool,
        uint256 positionId,
        uint16 percentage,
        uint256 amount0Min,
        uint256 amount1Min
    ) external override onlyCaller returns (uint256 amount0, uint256 amount1) {
        Position storage position = _positions[positionId];
        if (position.liquidity == 0) {
            revert InsufficientLiquidity(positionId);
        }

        uint128 newLiquidity = LibPercentageMath.multiplyU128(
            position.liquidity,
            percentage
        );

        (amount0, amount1) = IUniswapV3Pool(pool).burn(
            position.tickLower,
            position.tickUpper,
            newLiquidity
        );

        if (amount0 < amount0Min || amount1 < amount1Min) {
            revert PriceSlippageCheck();
        }

        UniswapV3PositionLib.updatePositionFeeGrowth(
            position,
            pool,
            newLiquidity
        );
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);
        position.liquidity -= newLiquidity;

        emit DecreaseLiquidity(positionId, newLiquidity, amount0, amount1);
    }

    function collect(
        address pool,
        uint256 positionId,
        address recipient,
        uint128 amount0Max,
        uint128 amount1Max
    ) external override onlyCaller returns (uint256 amount0, uint256 amount1) {
        if (amount0Max == 0 && amount1Max == 0) {
            revert InvalidCollectAmount();
        }

        recipient = recipient == address(0) ? address(this) : recipient;

        Position storage position = _positions[positionId];

        (uint128 tokensOwed0, uint128 tokensOwed1) = (
            position.tokensOwed0,
            position.tokensOwed1
        );

        if (position.liquidity > 0) {
            IUniswapV3Pool(pool).burn(
                position.tickLower,
                position.tickUpper,
                0
            );
            UniswapV3PositionLib.updatePositionFeeGrowth(
                position,
                pool,
                position.liquidity
            );
            tokensOwed0 = position.tokensOwed0;
            tokensOwed1 = position.tokensOwed1;
        }

        (uint128 amount0Collect, uint128 amount1Collect) = (
            amount0Max > tokensOwed0 ? tokensOwed0 : amount0Max,
            amount1Max > tokensOwed1 ? tokensOwed1 : amount1Max
        );

        (amount0, amount1) = IUniswapV3Pool(pool).collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        position.tokensOwed0 = tokensOwed0 - amount0Collect;
        position.tokensOwed1 = tokensOwed1 - amount1Collect;

        emit Collect(positionId, recipient, amount0Collect, amount1Collect);
    }
}
