// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract UniswapV3PoolTest {
    uint256 constant Q96 = 2**96;

    uint160 public pCurrentSqrt_Q96;
    uint128 public liquidity;

    function setParams(uint160 _pCurrentSqrt_Q96, uint128 _liquidity) external {
        pCurrentSqrt_Q96 = _pCurrentSqrt_Q96;
        liquidity = _liquidity;
    }

    function swap(
        address,
        bool zeroForOne,
        int256 amountSpecified,
        uint160,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        uint160 nextPrice_Q96 = SqrtPriceMath.getNextSqrtPriceFromInput(pCurrentSqrt_Q96, liquidity, uint256(amountSpecified), zeroForOne);
        if (zeroForOne) {
            amount1 = -int256(SqrtPriceMath.getAmount1Delta(nextPrice_Q96, pCurrentSqrt_Q96, liquidity, false));
            amount0 = amountSpecified;
        } else {
            amount0 = -int256(SqrtPriceMath.getAmount0Delta(nextPrice_Q96, pCurrentSqrt_Q96, liquidity, false));
            amount1 = amountSpecified;
        }
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
    }
}
