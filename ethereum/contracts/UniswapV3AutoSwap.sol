// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TokenPair} from "./interfaces/IUniswapV3TokenPairs.sol";
import {ISwapHandler} from "./interfaces/ISwapHandler.sol";

contract UniswapV3AutoSwap is ISwapHandler {
    using SafeERC20 for IERC20;

    address public swapRouter;
    address public swapPool;
    address public token0;
    address public token1;
    uint24 public fee;

    constructor(address _swapRouter, address _swapPool) {
        swapRouter = _swapRouter;
        swapPool = _swapPool;
        IUniswapV3Pool pool = IUniswapV3Pool(_swapPool);
        token0 = pool.token0();
        token1 = pool.token1();
        fee = pool.fee();
    }

    function swap(
        TokenPair memory tokenPair,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool zeroForOne // true: token0 -> token1, false: token1 -> token0
    ) external returns (uint256 amountOut) {
        address tokenIn = zeroForOne ? token0 : token1;
        address tokenOut = zeroForOne ? token1 : token0;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(swapPool, amountIn);
        IERC20(tokenIn).forceApprove(swapRouter, amountIn);

        if (isPoolLiquiditySufficient(amountIn, zeroForOne)) {
            amountOut = ISwapHandler(swapPool).swap(
                tokenPair,
                amountIn,
                amountOutMinimum,
                zeroForOne
            );
        } else {
            amountOut = ISwapHandler(swapRouter).swap(
                tokenPair,
                amountIn,
                amountOutMinimum,
                zeroForOne
            );
        }
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    function isPoolLiquiditySufficient(
        uint256 amountIn,
        bool zeroForOne
    ) public view returns (bool) {
        IUniswapV3Pool pool = IUniswapV3Pool(swapPool);
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
        uint128 liquidity = pool.liquidity();
        int24 tickSpacing = pool.tickSpacing();

        uint160 sqrtPriceNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
            sqrtPriceX96,
            liquidity,
            amountIn,
            zeroForOne
        );

        int24 tickLower = (tick / tickSpacing) * tickSpacing;
        return zeroForOne 
            ? sqrtPriceNextX96 >= TickMath.getSqrtRatioAtTick(tickLower)
            : sqrtPriceNextX96 <= TickMath.getSqrtRatioAtTick(tickLower + tickSpacing);
    }
}
