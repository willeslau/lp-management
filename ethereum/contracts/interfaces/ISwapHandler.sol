// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./IUniswapV3TokenPairs.sol";

interface ISwapHandler {
    /// @notice Execute token swap operation
    /// @param tokenPair Token pair information
    /// @param amountIn Input token amount
    /// @param amountOutMinimum Minimum output token amount
    /// @param isToken0ToToken1 Swap direction (true for token0 to token1, false for token1 to token0)
    /// @return amountOut Actual output token amount
    function swap(
        TokenPair memory tokenPair,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool isToken0ToToken1
    ) external returns (uint256 amountOut);
}
