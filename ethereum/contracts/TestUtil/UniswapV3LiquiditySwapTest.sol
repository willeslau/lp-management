// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {LiquiditySwapV3} from '../UniswapV3LiquiditySwap.sol';
import {ILiquiditySwapV3, CalculateParams, SearchRange} from "../interfaces/ILiquiditySwap.sol";

contract UniswapV3LiquiditySwapTest {
    event CalculatedTokenSwap(uint256 deltaToken0, uint256 deltaToken1);

    ILiquiditySwapV3 public calculator;

    constructor(address _calculator) {
        calculator = ILiquiditySwapV3(_calculator);
    }

    function calSwapToken1ForToken0(
        CalculateParams memory _params,
        SearchRange calldata _searchRange
    ) external {
        (bool isOk, uint256 amount1In, uint256 amountOut) = calculator.calSwapToken1ForToken0(_params, _searchRange);

        if (isOk) {
            emit CalculatedTokenSwap(amountOut, amount1In);
        }
        return;
    }
}
