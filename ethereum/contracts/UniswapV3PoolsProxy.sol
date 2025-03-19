// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {CallbackUtil} from "./Callback.sol";

import {MintParams, LiquidityChangeOutput} from "./interfaces/IUniswapV3PoolProxy.sol";
import {TokenPair, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
/// copy from https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/NonfungiblePositionManager.sol
contract UniswapV3PoolsProxy is CallbackUtil, IUniswapV3MintCallback {
    uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;
    using SafeERC20 for IERC20;

    struct MintCallbackData {
        address token0;
        address token1;
    }

    error PriceSlippageCheck();
    error U128Overflow(uint256 num);

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override checkCallbackFrom {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        if (amount0Owed > 0)
            IERC20(decoded.token0).safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0)
            IERC20(decoded.token1).safeTransfer(msg.sender, amount1Owed);
    }

    function _mint(
        TokenPair memory _tokenPair,
        MintParams memory _mintParams
    ) internal returns (LiquidityChangeOutput memory mintOutput) {
        return _addLiquidity(
            _tokenPair,
            _mintParams.tickLower,
            _mintParams.tickUpper,
            _mintParams.amount0Desired,
            _mintParams.amount1Desired,
            _mintParams.amount0Min,
            _mintParams.amount1Min
        );
    }

    function _burnWithSlippageCheck(
        IUniswapV3Pool _pool,
        uint128 _liquidityReduction,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (LiquidityChangeOutput memory output) {
        (uint256 amount0, uint256 amount1) = _pool.burn(
            _tickLower,
            _tickUpper,
            _liquidityReduction
        );

        if (
            amount0 < _amount0Min || amount1 < _amount1Min
        ) {
            revert PriceSlippageCheck();
        }

        output.amount0 = amount0;
        output.amount1 = amount1;
    }

    function _decreaseLiquidity(
        IUniswapV3Pool _pool,
        uint128 _liquidityReduction,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (LiquidityChangeOutput memory output) {
        (uint256 amount0, uint256 amount1) = _pool.burn(
            _tickLower,
            _tickUpper,
            _liquidityReduction
        );

        (uint128 amount0Collected, uint128 amount1Collected) = _pool.collect(
            address(this),
            _tickLower,
            _tickUpper,
            uint128(amount0),
            uint128(amount1)
        );

        if (
            uint128(amount0Collected) < _amount0Min ||
            uint256(amount1Collected) < _amount1Min
        ) {
            revert PriceSlippageCheck();
        }

        output.amount0 = uint256(amount0Collected);
        output.amount1 = uint256(amount1Collected);
    }

    function _safeCollect(
        IUniswapV3Pool _pool,
        address _recipient,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Requested,
        uint256 _amount1Requested
    ) internal returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = _pool.collect(
            _recipient,
            _tickLower,
            _tickUpper,
            _toU128(_amount0Requested),
            _toU128(_amount1Requested)
        );
    }

    function _toU128(uint256 _num) internal pure returns (uint128 v) {
        v = uint128(_num);
        if (uint256(v) != _num) {
            revert U128Overflow(_num);
        }
    }

    function _collectAll(
        IUniswapV3Pool _pool,
        address _recipient,
        int24 _tickLower,
        int24 _tickUpper
    ) internal returns (uint128 amount0, uint128 amount1) {
        (amount0, amount1) = _pool.collect(
            _recipient,
            _tickLower,
            _tickUpper,
            UINT128_MAX,
            UINT128_MAX
        );
    }

    /// @notice Add liquidity to an initialized pool
    function _addLiquidity(
        TokenPair memory _tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (LiquidityChangeOutput memory output) {
        IUniswapV3Pool pool = IUniswapV3Pool(_tokenPair.pool);

        // compute the liquidity amount
        uint128 liquidity;
        {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                _amount0Desired,
                _amount1Desired
            );
        }

        _expectCallbackFrom(_tokenPair.pool);
        bytes memory m = abi.encode(
            MintCallbackData({
                token0: _tokenPair.token0,
                token1: _tokenPair.token1
            })
        );
        (output.amount0 , output.amount1) = pool.mint(
            address(this),
            _tickLower,
            _tickUpper,
            liquidity,
            m
        );

        if (output.amount0 < _amount0Min || output.amount1 < _amount1Min) revert PriceSlippageCheck();
    }

    function _tokensOwned(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    )
        internal
        view
        returns (
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes32 uniswapPositionKey = _uniswapPositionKey(_tickLower, _tickUpper);
        (, , , tokensOwed0, tokensOwed1) = _pool.positions(uniswapPositionKey);
    }

    function _position(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    )
        public
        view
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes32 uniswapPositionKey = _uniswapPositionKey(_tickLower, _tickUpper);

        (liquidity, , , tokensOwed0, tokensOwed1) = _pool.positions(
            uniswapPositionKey
        );

        (uint160 sqrtPriceX96, , , , , , ) = _pool.slot0();

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity
        );
    }

    function _uniswapPositionKey(
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns(bytes32) {
        return PositionKey.compute(
            address(this),
            _tickLower,
            _tickUpper
        );
    }

    function _positionLiquidity(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) public view returns (uint128 liquidity) {
        bytes32 uniswapPositionKey = _uniswapPositionKey(_tickLower, _tickUpper);
        (liquidity, , , , ) = _pool.positions(uniswapPositionKey);
    }
}
