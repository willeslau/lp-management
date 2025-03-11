// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TokenPair} from "./interfaces/IUniswapV3TokenPairs.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

abstract contract UniswapV3SwapPool is IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    address public immutable swapFactory;

    error InvalidPool();
    error PoolNotExist();
    error InsufficientOutputAmount();

    constructor(address _factory) {
        swapFactory = _factory;
    }

    function uniswapV3SwapCallback(
        int256,
        int256,
        bytes calldata data
    ) external view override {
        (address tokenIn, address tokenOut, uint24 poolFee) = abi.decode(
            data,
            (address, address, uint24)
        );

        address pool = IUniswapV3Factory(swapFactory).getPool(
            tokenIn,
            tokenOut,
            poolFee
        );
        if (msg.sender != pool) {
            revert InvalidPool();
        }
    }

    /// @notice Swap tokens directly using UniswapV3Pool
    /// @param token0 token0 address
    /// @param token1 token1 address
    /// @param fee pool fee
    /// @param amountIn Input token amount
    /// @param amountOutMinimum Minimum output token amount
    /// @param isToken0ToToken1 Swap direction
    /// @return amountOut Actual output token amount
    function _swap(
        address token0,
        address token1,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool isToken0ToToken1
    ) internal returns (uint256 amountOut) {
        address tokenIn = isToken0ToToken1 ? token0 : token1;
        address tokenOut = isToken0ToToken1 ? token1 : token0;

        address pool = IUniswapV3Factory(swapFactory).getPool(
            token0,
            token1,
            fee
        );
        if (pool == address(0)) {
            revert PoolNotExist();
        }

        _approveIfNeeded(tokenIn, pool, amountIn);

        uint160 sqrtPriceLimitX96 = 0;

        bytes memory callbackData = abi.encode(tokenIn, tokenOut, fee);

        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            address(this),
            isToken0ToToken1,
            int256(amountIn),
            sqrtPriceLimitX96,
            callbackData
        );

        amountOut = uint256(-(isToken0ToToken1 ? amount1 : amount0));
        if (amountOut < amountOutMinimum) {
            revert InsufficientOutputAmount();
        }
    }

    function _approveIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            IERC20(token).forceApprove(spender, amount);
        }
    }
}
