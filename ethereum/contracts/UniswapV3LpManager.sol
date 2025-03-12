// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";

import {LibPercentageMath} from "./RateMath.sol";
import {UniswapV3PositionLib, Position, MintParams} from "./libraries/UniswapV3PositionLib.sol";

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
contract UniswapV3LpManager is LiquidityManagement {
    error InvalidTokenId();
    error InsufficientLiquidity();
    error PriceSlippageCheck();
    error InvalidCollectAmount();
    error PositionNotCleared();

    /// @notice Emitted when liquidity is increased for a position NFT
    /// @dev Also emitted when a token is minted
    /// @param tokenId The ID of the token for which liquidity was increased
    /// @param liquidity The amount by which liquidity for the NFT position was increased
    /// @param amount0 The amount of token0 that was paid for the increase in liquidity
    /// @param amount1 The amount of token1 that was paid for the increase in liquidity
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when liquidity is decreased for a position NFT
    /// @param tokenId The ID of the token for which liquidity was decreased
    /// @param liquidity The amount by which liquidity for the NFT position was decreased
    /// @param amount0 The amount of token0 that was accounted for the decrease in liquidity
    /// @param amount1 The amount of token1 that was accounted for the decrease in liquidity
    event DecreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when tokens are collected for a position NFT
    /// @dev The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior
    /// @param tokenId The ID of the token for which underlying tokens were collected
    /// @param recipient The address of the account that received the collected tokens
    /// @param amount0 The amount of token0 owed to the position that was collected
    /// @param amount1 The amount of token1 owed to the position that was collected
    event Collect(
        uint256 indexed tokenId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when a new position is created
    /// @param tokenId The ID of the token for which position was created
    /// @param liquidity The amount of liquidity provided for the position
    /// @param amount0 The amount of token0 used to create the position
    /// @param amount1 The amount of token1 used to create the position
    event PositionCreated(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

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
    ) PeripheryImmutableState(_factory, _WETH9) {}

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        if (position.poolId == 0) {
            revert InvalidTokenId();
        }

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

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

    function burn(uint256 tokenId) external {
        Position storage position = _positions[tokenId];
        if (
            position.liquidity != 0 ||
            position.tokensOwed0 != 0 ||
            position.tokensOwed1 != 0
        ) revert PositionNotCleared();
        delete _positions[tokenId];
    }

    /// @dev Gets pool instance and pool key for a position
    function getPoolInfo(
        Position memory position
    )
        public
        view
        returns (IUniswapV3Pool pool, PoolAddress.PoolKey memory poolKey)
    {
        poolKey = _poolIdToPoolKey[position.poolId];
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
    }

    function mint(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint16 maxMintSlippageRate
    )
        external
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        MintParams memory params = MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
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
        AddLiquidityParams memory addParams = _setupAddLiquidityParams(
            params,
            amount0Min,
            amount1Min
        );

        tokenId = _nextId++;
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
                token0: params.token0,
                token1: params.token1,
                fee: params.fee
            })
        );

        UniswapV3PositionLib.createPosition(
            _positions,
            tokenId,
            poolId,
            params.tickLower,
            params.tickUpper,
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128
        );

        emit PositionCreated(tokenId, liquidity, amount0, amount1);
    }

    function _setupAddLiquidityParams(
        MintParams memory params,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal view returns (AddLiquidityParams memory) {
        return
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min
            });
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        Position storage position = _positions[tokenId];
        (IUniswapV3Pool pool, PoolAddress.PoolKey memory poolKey) = getPoolInfo(
            position
        );

        (liquidity, amount0, amount1, ) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
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
            pool,
            position.liquidity
        );
        position.liquidity += liquidity;

        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) public returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) {
            revert InsufficientLiquidity();
        }

        Position storage position = _positions[tokenId];

        uint128 positionLiquidity = position.liquidity;
        if (positionLiquidity < liquidity) {
            revert InsufficientLiquidity();
        }

        (IUniswapV3Pool pool, ) = getPoolInfo(position);
        (amount0, amount1) = pool.burn(
            position.tickLower,
            position.tickUpper,
            liquidity
        );

        if (amount0 < amount0Min || amount1 < amount1Min) {
            revert PriceSlippageCheck();
        }

        UniswapV3PositionLib.updatePositionFeeGrowth(
            position,
            pool,
            positionLiquidity
        );
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);
        position.liquidity = positionLiquidity - liquidity;

        emit DecreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    function collect(
        uint256 tokenId,
        address recipient,
        uint128 amount0Max,
        uint128 amount1Max
    )
        public
        returns (
            uint256 amount0,
            uint256 amount1,
            PoolAddress.PoolKey memory poolKey
        )
    {
        if (amount0Max == 0 && amount1Max == 0) {
            revert InvalidCollectAmount();
        }

        recipient = recipient == address(0) ? address(this) : recipient;

        Position storage position = _positions[tokenId];
        IUniswapV3Pool pool;
        (pool, poolKey) = getPoolInfo(position);

        (uint128 tokensOwed0, uint128 tokensOwed1) = (
            position.tokensOwed0,
            position.tokensOwed1
        );

        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
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

        (amount0, amount1) = pool.collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        position.tokensOwed0 = tokensOwed0 - amount0Collect;
        position.tokensOwed1 = tokensOwed1 - amount1Collect;

        emit Collect(tokenId, recipient, amount0Collect, amount1Collect);
    }
}
