// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {CallbackUtil} from "./Callback.sol";

import {IUniswapV3PoolProxy, MintParams, LiquidityChangeOutput} from "./interfaces/IUniswapV3PoolProxy.sol";
import {TokenPair, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";

import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
/// copy from https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/NonfungiblePositionManager.sol
contract UniswapV3PoolProxy is
    IUniswapV3PoolProxy,
    Ownable,
    CallbackUtil,
    IUniswapV3MintCallback
{
    using SafeERC20 for IERC20;

    struct MintCallbackData {
        address token0;
        address token1;
    }

    error PriceSlippageCheck();

    /// @inheritdoc IUniswapV3MintCallback
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override checkCallbackFrom {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        address owner = owner();
        if (amount0Owed > 0)
            IERC20(decoded.token0).safeTransferFrom(
                owner,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            IERC20(decoded.token1).safeTransferFrom(
                owner,
                msg.sender,
                amount1Owed
            );
    }

    function mint(
        TokenPair calldata _tokenPair,
        MintParams calldata _mintParams
    )
        external
        override
        onlyOwner
        returns (LiquidityChangeOutput memory mintOutput)
    {
        (, uint256 amount0, uint256 amount1) = _addLiquidity(
            _tokenPair,
            _mintParams.tickLower,
            _mintParams.tickUpper,
            _mintParams.amount0Desired,
            _mintParams.amount1Desired,
            _mintParams.amount0Min,
            _mintParams.amount1Min
        );

        mintOutput.amount0 = amount0;
        mintOutput.amount1 = amount1;
    }

    function increaseLiquidity(
        TokenPair memory tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    )
        external
        override
        onlyOwner
        returns (LiquidityChangeOutput memory output)
    {
        (, uint256 amount0, uint256 amount1) = _addLiquidity(
            tokenPair,
            _tickLower,
            _tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );

        output.amount0 = amount0;
        output.amount1 = amount1;
    }

    function decreaseLiquidity(
        IUniswapV3Pool _pool,
        uint128 _liquidityReduction,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min
    )
        external
        override
        onlyOwner
        returns (LiquidityChangeOutput memory output)
    {
        (uint256 amount0, uint256 amount1) = _pool.burn(
            _tickLower,
            _tickUpper,
            _liquidityReduction
        );

        if (amount0 < _amount0Min || amount1 < _amount1Min) {
            revert PriceSlippageCheck();
        }

        output.amount0 = amount0;
        output.amount1 = amount1;
    }

    function collect(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) external override onlyOwner returns (uint256 amount0, uint256 amount1) {
        (, uint128 fee0, uint128 fee1) = position(
            _pool,
            _tickLower,
            _tickUpper
        );
        (amount0, amount1) = _pool.collect(
            address(this),
            _tickLower,
            _tickUpper,
            fee0,
            fee1
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
    ) internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = IUniswapV3Pool(_tokenPair.pool);

        // compute the liquidity amount
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

        (amount0, amount1) = pool.mint(
            address(this),
            _tickLower,
            _tickUpper,
            liquidity,
            abi.encode(
                MintCallbackData({
                    token0: _tokenPair.token0,
                    token1: _tokenPair.token1
                })
            )
        );

        if (amount0 < _amount0Min || amount1 < _amount1Min)
            revert PriceSlippageCheck();
    }

    function position(
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper
    )
        public
        view
        returns (uint128 liquidity, uint128 tokensOwed0, uint128 tokensOwed1)
    {
        bytes32 uniswapPositionKey = PositionKey.compute(
            address(this),
            _tickLower,
            _tickUpper
        );
        (liquidity, , , tokensOwed0, tokensOwed1) = _pool.positions(
            uniswapPositionKey
        );
    }

    function fund() internal {
        // todo: send funds back to caller
    }
}
