// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ILiquiditySwapV3, CalculateParams, SearchRange} from "./interfaces/ILiquiditySwap.sol";

import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IQuoterV2} from '@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol';
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract LiquiditySwapV3 is ILiquiditySwapV3 {
    uint256 constant Q96 = 2**96;

    IQuoterV2 public quoter;

    /**
     * @notice Computes the Uniswap V3 ratio R in Q96 form
     *         R = (sqrtP - sqrtPa) / (1/sqrtP - 1/sqrtPb).
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

        // denominator_Q96 = (1/sqrtP - 1/sqrtPb) in Q96
        //               = (sqrtPb - sqrtP) / (sqrtPb * sqrtP)
        uint256 denominator_Q96 =  _divQ96(sqrtPb_Q96 - sqrtP_Q96, sqrtPb_Q96);
        denominator_Q96 =  _divQ96(denominator_Q96, sqrtP_Q96);

        // R_Q96 = (sqrtP_Q96 - sqrtPa_Q96) / denominator_Q96 in Q96
        return _divQ96(sqrtP_Q96 - sqrtPa_Q96, denominator_Q96);
    }

    function calSwapToken1ForToken0(
        CalculateParams memory _params,
        SearchRange calldata _searchRange
    ) external returns(bool, uint256, uint256) {
        uint256 low = _searchRange.swapInLow;
        uint256 hig = _searchRange.swapInHigh;

        uint256 mid;

        for (uint8 i = 0; i < _searchRange.searchLoopNum;) {
            mid = low + (hig - low) / 2;

            (bool isOk, uint256 amountOut) = _swapToken1ForToken0AgainstR(_params, mid);
            
            if (isOk) {
                // found the solution
                return (true, mid, amountOut);
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
    ) external returns(bool, uint256, uint256) {
        uint256 low = _searchRange.swapInLow;
        uint256 hig = _searchRange.swapInHigh;

        uint256 mid;

        for (uint8 i = 0; i < _searchRange.searchLoopNum;) {
            mid = low + (hig - low) / 2;

            (bool isOk, uint256 amountOut) = _swapToken0ForToken1AgainstR(_params, mid);
            
            if (isOk) {
                // found the solution
                return (true, mid, amountOut);
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
        uint256 _delta0
    ) internal returns(bool isOk, uint256 amount1Out) {
        (amount1Out, , ,) = quoter.quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: _params.token0,
            tokenOut: _params.token1,
            amountIn: _delta0,
            fee: _params.poolFee,
            sqrtPriceLimitX96: _params.sqrtPSlippage_Q96
        }));

        return (
            _isPostSwapROk(_params.amount0 - _delta0, _params.amount1 + _delta0, _params.R_Q96, _params.REpslon_Q96), 
            amount1Out
        );
    }

    function _swapToken1ForToken0AgainstR(
        CalculateParams memory _params,
        uint256 _delta1
    ) internal returns(bool isOk, uint256 amount0Out) {
        (amount0Out, , ,) = quoter.quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: _params.token1,
            tokenOut: _params.token0,
            amountIn: _delta1,
            fee: _params.poolFee,
            sqrtPriceLimitX96: _params.sqrtPSlippage_Q96
        }));

        return (
            _isPostSwapROk(_params.amount0 + amount0Out, _params.amount1 - _delta1, _params.R_Q96, _params.REpslon_Q96), 
            amount0Out
        );
    }

    function _isPostSwapROk(uint256 _newAmount0, uint256 _newAmount1, uint256 _R_Q96, uint256 _REpslon_Q96) internal pure returns (bool) {
        uint256 r = _divQ96(_newAmount0, _newAmount1);

        uint256 rDelta_Q96 = _divQ96(
            _absSub(_R_Q96, r), 
            _R_Q96
        );

        return rDelta_Q96 < _REpslon_Q96;
    }

    function _divQ96(uint256 a, uint256 b) internal pure returns(uint256) {
        return FullMath.mulDiv(a, Q96, b);
    }

    function _absSub(uint256 a, uint256 b) internal pure returns(uint256) {
        return a > b ? a - b : b - a;
    }

}