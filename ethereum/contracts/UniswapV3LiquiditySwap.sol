// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ILiquiditySwapV3, CalculateParams, SearchRange} from "./interfaces/ILiquiditySwap.sol";

import {IQuoterV2} from '@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol';
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

enum CompareResult {
    InRange,
    AboveRange,
    BelowRange
}

contract LiquiditySwapV3 is ILiquiditySwapV3 {
    uint256 constant Q96 = 2**96;

    IQuoterV2 public quoter;

    constructor(address _quoter) {
        quoter = IQuoterV2(_quoter);
    }

    /**
     * @notice Computes the Uniswap V3 ratio R in Q96 form
     *         R = (sqrtP - sqrtPa) / (1/sqrtP - 1/sqrtPb)
     *         R = = (sqrtP - sqrtPa) / [(sqrtPb - sqrtP) / (sqrtPb * sqrtP)]
     *         R = = (sqrtP - sqrtPa) * sqrtPb * sqrtP / (sqrtPb - sqrtP)
     * @param sqrtP_Q96   current sqrt-price in Q96
     * @param sqrtPa_Q96  lower bound sqrt-price in Q96
     * @param sqrtPb_Q96  upper bound sqrt-price in Q96
     * @return R_Q96 The ratio as a Q96-scaled integer
     */
    function computeR(
        uint160 sqrtP_Q96,
        uint160 sqrtPa_Q96,
        uint160 sqrtPb_Q96
    ) public pure returns (uint256) {
        if (!(sqrtPa_Q96 <= sqrtP_Q96 && sqrtP_Q96 <= sqrtPb_Q96)) {
            revert("invalid range");
        }

        uint256 tmp = FullMath.mulDiv(sqrtP_Q96, sqrtPb_Q96, Q96);
        return FullMath.mulDiv(sqrtP_Q96 - sqrtPa_Q96, tmp, sqrtPb_Q96 - sqrtP_Q96);
    }

    function calSwapToken1ForToken0(
        CalculateParams memory _params,
        SearchRange calldata _searchRange
    ) external returns(bool, uint256 amount1In, uint256 amountOut) {
        uint256 low = _searchRange.swapInLow;
        uint256 hig = _searchRange.swapInHigh;

        CompareResult r;
        
        for (uint8 i = 0; i < _searchRange.searchLoopNum;) {
            amount1In = low + (hig - low) / 2;

            (r, amountOut) = _swapToken1ForToken0AgainstR(_params, _searchRange, amount1In);
            
            if (r == CompareResult.InRange) {
                return (true, amount1In, amountOut);
            } else if (r == CompareResult.AboveRange) {
                low = amount1In + 1 wei; 
            } else {
                hig = amount1In - 1 wei;
                
            }

            unchecked {
                i++;
            }
        }

        // no solution found
        return (false, 0, 0);
    }

    function calSwapToken0ForToken1(
        CalculateParams memory _params,
        SearchRange calldata _searchRange
    ) external returns(bool, uint256 amount0In, uint256 amount1Out) {
        uint256 low = _searchRange.swapInLow;
        uint256 hig = _searchRange.swapInHigh;

        CompareResult r;

        for (uint8 i = 0; i < _searchRange.searchLoopNum;) {
            amount0In = low + (hig - low) / 2;

            (r, amount1Out) = _swapToken0ForToken1AgainstR(_params, _searchRange, amount0In);
            
            if (r == CompareResult.InRange) {
                // found the solution
                return (true, amount0In, amount1Out);
            } else if (r == CompareResult.AboveRange) {
                hig = amount0In - 1 ether; 
            } else {
                low = amount0In + 1 ether;
            }

            unchecked {
                i++;
            }
        }

        // no solution found
        return (false, 0, 0);
    }

    function _swapToken0ForToken1AgainstR(
        CalculateParams memory _params,
        SearchRange calldata _searchRange,
        uint256 _delta0
    ) internal returns(CompareResult, uint256 amount1Out) {
        (amount1Out, , ,) = quoter.quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: _params.token0,
            tokenOut: _params.token1,
            amountIn: _delta0,
            fee: _params.poolFee,
            sqrtPriceLimitX96: _params.sqrtPSlippage_Q96
        }));

        return (
            _isPostSwapROk(_params.amount0 - _delta0, _params.amount1 + amount1Out, _params.R_Q96, _searchRange.REpslon_Q96), 
            amount1Out
        );
    }

    function _swapToken1ForToken0AgainstR(
        CalculateParams memory _params,
        SearchRange calldata _searchRange,
        uint256 _delta1
    ) internal returns(CompareResult, uint256 amount0Out) {
        (amount0Out, , ,) = quoter.quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: _params.token1,
            tokenOut: _params.token0,
            amountIn: _delta1,
            fee: _params.poolFee,
            sqrtPriceLimitX96: _params.sqrtPSlippage_Q96
        }));

        return (
            _isPostSwapROk(_params.amount0 + amount0Out, _params.amount1 - _delta1, _params.R_Q96, _searchRange.REpslon_Q96), 
            amount0Out
        );
    }

    function _isPostSwapROk(uint256 _newAmount0, uint256 _newAmount1, uint256 _R_Q96, uint256 _REpslon_Q96) internal pure returns (CompareResult) {
        uint256 r = _divQ96(_newAmount1 * Q96, _newAmount0 * Q96);

        uint256 rDelta_Q96 = 0;

        if (r < _R_Q96) {
            rDelta_Q96 = _divQ96(_R_Q96 - r, _R_Q96);
            if (rDelta_Q96 < _REpslon_Q96) {
                return CompareResult.InRange;
            }
            return CompareResult.BelowRange;
        }

        rDelta_Q96 = _divQ96(r - _R_Q96, _R_Q96);
        if (rDelta_Q96 < _REpslon_Q96) {
            return CompareResult.InRange;
        }
        return CompareResult.AboveRange;
    }

    function _divQ96(uint256 a, uint256 b) internal pure returns(uint256) {
        return FullMath.mulDiv(a, Q96, b);
    }
}