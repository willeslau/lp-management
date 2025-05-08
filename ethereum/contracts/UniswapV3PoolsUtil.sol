// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";

import {CallbackUtil} from "./Callback.sol";

import {LiquidityChangeOutput} from "./interfaces/IUniswapV3PoolProxy.sol";
import {PositionInfo} from "./libraries/LibVault.sol";
import {TokenPair, TokenPairAdresses, IUniswapV3TokenPairs, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";
import {BurnSlippageError, UniswapCallFailed} from "./Errors.sol";

/// @title Uniswap V3 Position Manager Util
/// @notice Manages Uniswap V3 liquidity positions
/// copy from https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/NonfungiblePositionManager.sol
contract UniswapV3PoolsUtil is CallbackUtil {
    using SafeERC20 for IERC20;

    struct MintCallbackData {
        address token0;
        address token1;
    }

    function pancakeV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external checkCallbackFrom {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external checkCallbackFrom {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function _mintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) internal {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        if (amount0Owed > 0)
            IERC20(decoded.token0).safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0)
            IERC20(decoded.token1).safeTransfer(msg.sender, amount1Owed);
    }

    function _slot0(
        address _pool
    ) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        // using low level call instead as we want to parse the data ourselves.
        // why do we do this? Because we want to support both uniswap and pancakeswap
        // uniswap.slot0.fee is uint8 but pancakeswap is u32
        (bool success, bytes memory data) = _pool.staticcall(
            abi.encodeWithSignature("slot0()")
        );
        require(success, "sf");

        (sqrtPriceX96, tick) = abi.decode(data, (uint160, int24));
    }

    function _burnWithSlippageCheck(
        IUniswapV3Pool _pool,
        uint128 _liquidityReduction,
        PositionInfo memory _positionInfo,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (LiquidityChangeOutput memory output) {
        (output.amount0, output.amount1) = _pool.burn(
            _positionInfo.tickLower,
            _positionInfo.tickUpper,
            _liquidityReduction
        );

        if (output.amount0 < _amount0Min || output.amount1 < _amount1Min) {
            revert BurnSlippageError();
        }

        output.liquidity = _positionLiquidity(_pool, _positionInfo);
    }

    function _collect(
        IUniswapV3Pool _pool,
        address _recipient,
        PositionInfo memory _positionInfo,
        uint128 _amount0Requested,
        uint128 _amount1Requested
    ) internal returns (uint128 amount0, uint128 amount1) {
        try
            _pool.collect(
                _recipient,
                _positionInfo.tickLower,
                _positionInfo.tickUpper,
                _amount0Requested,
                _amount1Requested
            )
        returns (uint128 a0, uint128 a1) {
            amount0 = a0;
            amount1 = a1;
        } catch (bytes memory reason) {
            revert UniswapCallFailed("ca", reason);
        }
    }

    /// @notice Add liquidity to an initialized pool
    function _addLiquidity(
        TokenPairAdresses memory _tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Desired,
        uint256 _amount1Desired
    ) internal returns (LiquidityChangeOutput memory output) {
        IUniswapV3Pool pool = IUniswapV3Pool(_tokenPair.pool);

        {
            (uint160 sqrtPriceX96, ) = _slot0(_tokenPair.pool);
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

            output.liquidity = LiquidityAmounts.getLiquidityForAmounts(
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

        try
            pool.mint(address(this), _tickLower, _tickUpper, output.liquidity, m)
        returns (uint256 a0, uint256 a1) {
            output.amount0 = a0;
            output.amount1 = a1;
        } catch (bytes memory reason) {
            revert UniswapCallFailed("am", reason);
        }
    }

    function _tokensOwned(
        IUniswapV3Pool _pool,
        PositionInfo memory _positionInfo
    ) internal view returns (uint128 tokensOwed0, uint128 tokensOwed1) {
        bytes32 uniswapPositionKey = _uniswapPositionKey(_positionInfo);
        (, , , tokensOwed0, tokensOwed1) = _pool.positions(uniswapPositionKey);
    }

    function _uniswapPositionKey(
        PositionInfo memory _positionInfo
    ) internal view returns (bytes32) {
        return
            PositionKey.compute(
                address(this),
                _positionInfo.tickLower,
                _positionInfo.tickUpper
            );
    }

    function _positionLiquidity(
        IUniswapV3Pool _pool,
        PositionInfo memory _positionInfo
    ) public view returns (uint128 liquidity) {
        bytes32 uniswapPositionKey = _uniswapPositionKey(_positionInfo);
        (liquidity, , , , ) = _pool.positions(uniswapPositionKey);
    }
}
