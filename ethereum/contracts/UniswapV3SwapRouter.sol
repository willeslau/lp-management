// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./interfaces/IUniswapV3TokenPairs.sol";
import "./interfaces/ISwapHandler.sol";

error PoolNotExist();
error InvalidPool();
error InsufficientOutputAmount();

contract UniswapV3SwapRouter is ISwapHandler {
    using SafeERC20 for IERC20;

    address public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @notice Swap tokens using SwapRouter's ExactInputSingle
    /// @param tokenPair Token pair information
    /// @param amountIn Input token amount
    /// @param amountOutMinimum Minimum output token amount
    /// @param isToken0ToToken1 Swap direction
    /// @return amountOut Actual output token amount
    function swap(
        TokenPair memory tokenPair,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool isToken0ToToken1
    ) external returns (uint256 amountOut) {
        address tokenIn = isToken0ToToken1
            ? tokenPair.token0
            : tokenPair.token1;
        address tokenOut = isToken0ToToken1
            ? tokenPair.token1
            : tokenPair.token0;

        _approveIfNeeded(tokenIn, swapRouter, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: tokenPair.poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        amountOut = ISwapRouter(swapRouter).exactInputSingle(params);
        if (amountOut < amountOutMinimum) {
            revert InsufficientOutputAmount();
        }
    }

    /// @notice Check and approve token allowance
    /// @param token Token address
    /// @param spender Spender address
    /// @param amount Approval amount
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
