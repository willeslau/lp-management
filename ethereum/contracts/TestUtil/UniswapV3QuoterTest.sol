// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IQuoterV2} from '@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol';
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract UniswapV3QuoterTest is IQuoterV2 {
    uint256 constant Q96 = 2**96;

    uint256 public pCurrentSqrt_Q96;
    uint256 public liquidity;

    function setParams(uint256 _pCurrentSqrt_Q96, uint256 _liquidity) external {
        pCurrentSqrt_Q96 = _pCurrentSqrt_Q96;
        liquidity = _liquidity;
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
            // swap token 1 for token 0
            if (_params.tokenOut == address(0)) {
                uint256 t = FullMath.mulDiv(_params.amountIn, Q96, liquidity);
                t += pCurrentSqrt_Q96;
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
