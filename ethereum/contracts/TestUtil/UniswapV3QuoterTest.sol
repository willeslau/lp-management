// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IQuoterV2} from '@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol';
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

contract UniswapV3QuoterTest is IQuoterV2 {
    uint256 constant Q96 = 2**96;

    uint256 public pCurrentSqrt_Q96;
    uint256 public liquidity;
    bool public zeroForOne;

    function setParams(uint256 _pCurrentSqrt_Q96, uint256 _liquidity, bool _zeroForOne) external {
        pCurrentSqrt_Q96 = _pCurrentSqrt_Q96;
        liquidity = _liquidity;
        zeroForOne = _zeroForOne;
    }

    function quoteExactInput(bytes memory , uint256 )
        external
        view
        returns (
            uint256 amountOut,
            uint160[] memory ,
            uint32[] memory ,
            uint256 
        ) {
        }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory _params)
        external
        view
        returns (
            uint256 amountOut,
            uint160 ,
            uint32 ,
            uint256 
        ) {
            if (zeroForOne) {
                uint160 nextPrice_Q96 = SqrtPriceMath.getNextSqrtPriceFromInput(uint160(pCurrentSqrt_Q96), uint128(liquidity), _params.amountIn, true);
                amountOut = SqrtPriceMath.getAmount1Delta(uint160(nextPrice_Q96), uint160(pCurrentSqrt_Q96), uint128(liquidity), false);
            } else {
                uint256 t = FullMath.mulDiv(_params.amountIn, Q96, liquidity) + pCurrentSqrt_Q96;
                t = FullMath.mulDiv(t, pCurrentSqrt_Q96, Q96);
                amountOut = FullMath.mulDiv(_params.amountIn, Q96, t);
            }
        }

    function quoteExactOutput(bytes memory , uint256 )
        external
        view
        returns (
            uint256 amountIn,
            uint160[] memory ,
            uint32[] memory ,
            uint256 
        ) {

        }

    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory )
        external
        view
        returns (
            uint256 ,
            uint160 ,
            uint32 ,
            uint256 
        ) {

        }
}
