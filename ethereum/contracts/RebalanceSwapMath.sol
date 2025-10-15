// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

struct QuoteParams {
    bool zeroForOne;
    uint160 priceLimitSqrt;
    uint256 priceLimit;
}

interface IRebalanceSwapMath {
    function calculateSwapState(
        address _pool,
        QuoteParams calldata _quoteParams,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1
    )
        external
        view
        returns (int256 swapAmount0, int256 swapAmount1, int256 minAmountOut);
}

/// @title Uniswap V3 LP Manager Rebalance Swap Math
contract RebalanceSwapMath {
    uint256 public constant PRICE_BASE = 1 ether;
    int256 public constant SLIPPAGE_BASE = int256(1 ether);
    uint128 public constant DUMMY_LIQUIDITY = uint128(1 ether);

    /// @dev Intermediate memory data structure for swap calculation
    struct SwapState {
        bool zeroForOne;
        uint256 rNum;
        uint256 rDen;
        int256 swapAmount0;
        int256 swapAmount1;
    }

    /// @notice The ticks are not correct.
    /// @dev When reason == 0, tick (b) does not lie on tick spacing(a).
    ///      When reason == 1, tick current (a) is smaller than tick lower (b).
    ///      When reason == 2, tick current (a) is greater than tick upper (b).
    error InvalidTick(uint8 reason, int24 a, int24 b);
    error SwapDirectionInvalid(bool expected, bool actual);
    error DeltaInvariantBroken(SwapState s, uint256 num1, uint256 num2);
    error Int256OverflowOrUnderflow(uint256 num);
    error ZeroForOnePriceLimitTooBig(uint160 priceSqrt);
    error OneForZeroPriceLimitTooBig(uint160 priceSqrt);
    error SwapAmountOutTooSmall(int256 amountOut, SwapState swap);
    error InvalidR(uint160 upper, uint160 lower);
    error BothTokenZero();

    function calculateSwapState(
        address _pool,
        QuoteParams calldata _quoteParams,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 _amount0,
        uint256 _amount1
    ) external view returns (int256, int256, int256) {
        SwapState memory swapState;

        (uint160 priceRatioX96, int24 tick) = _slot0(_pool);

        _sanityCheckTickRange(_pool, tick, _tickLower, _tickUpper);

        // deduce the target token ratio
        (swapState.rNum, swapState.rDen) = _tokenRatio(
            priceRatioX96,
            _tickLower,
            _tickUpper
        );

        swapState.zeroForOne = _isZeroForOne(swapState, _amount0, _amount1);
        if (swapState.zeroForOne != _quoteParams.zeroForOne) {
            revert SwapDirectionInvalid(
                _quoteParams.zeroForOne,
                swapState.zeroForOne
            );
        }

        _updateSwapAmount(
            _amount0,
            _amount1,
            swapState,
            _quoteParams.priceLimit
        );

        int256 amountOutMin = _slippageCheck(
            swapState,
            _quoteParams,
            priceRatioX96
        );

        return (swapState.swapAmount0, swapState.swapAmount1, amountOutMin);
    }

    // ==================== Internal Methods ====================

    function _slippageCheck(
        SwapState memory _swap,
        QuoteParams calldata _quoteParams,
        uint160 _currentPriceSqrt
    ) internal pure returns (int256 amountOutMin) {
        if (_swap.zeroForOne) {
            if (_currentPriceSqrt <= _quoteParams.priceLimitSqrt) {
                revert ZeroForOnePriceLimitTooBig(_currentPriceSqrt);
            }

            amountOutMin =
                (_uint256ToInt256(_quoteParams.priceLimit) *
                    _swap.swapAmount0) /
                int256(PRICE_BASE);
            if (amountOutMin > _swap.swapAmount1) {
                revert SwapAmountOutTooSmall(amountOutMin, _swap);
            }
        } else {
            if (_currentPriceSqrt >= _quoteParams.priceLimitSqrt) {
                revert OneForZeroPriceLimitTooBig(_currentPriceSqrt);
            }
            amountOutMin = _uint256ToInt256(
                FullMath.mulDiv(
                    PRICE_BASE,
                    uint256(_swap.swapAmount1),
                    _quoteParams.priceLimit
                )
            );
            if (amountOutMin > _swap.swapAmount0) {
                revert SwapAmountOutTooSmall(amountOutMin, _swap);
            }
        }
    }

    function _updateSwapAmount(
        uint256 _amount0,
        uint256 _amount1,
        SwapState memory _swap,
        uint256 _scaledPrice
    ) internal pure {
        uint256 num1 = FullMath.mulDiv(_amount1, _swap.rNum, _swap.rDen);
        uint256 num2 = _amount0;

        uint256 den = PRICE_BASE +
            FullMath.mulDiv(_scaledPrice, _swap.rNum, _swap.rDen);

        uint256 delta0 = 0;
        if (_swap.zeroForOne) {
            if (num1 > num2) {
                revert DeltaInvariantBroken(_swap, num1, num2);
            }

            delta0 = FullMath.mulDiv(PRICE_BASE, (num2 - num1), den);
        } else {
            if (num1 < num2) {
                revert DeltaInvariantBroken(_swap, num1, num2);
            }

            delta0 = FullMath.mulDiv(PRICE_BASE, (num1 - num2), den);
        }

        uint256 delta1 = (delta0 * _scaledPrice) / PRICE_BASE;

        _swap.swapAmount0 = _uint256ToInt256(delta0);
        _swap.swapAmount1 = _uint256ToInt256(delta1);
    }

    function _tokenRatio(
        uint160 _sqrtPriceX96,
        int24 _tickLower,
        int24 _tickUpper
    ) internal pure returns (uint256 numberator, uint256 denominator) {
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

        // use dummy liquidity is fine as we are interested in the token ratio
        (numberator, denominator) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtPriceX96,
            sqrtPriceLowerX96,
            sqrtPriceUpperX96,
            DUMMY_LIQUIDITY
        );

        if (denominator == 0)
            revert InvalidR(sqrtPriceLowerX96, sqrtPriceUpperX96);
    }

    function _isZeroForOne(
        SwapState memory _state,
        uint256 _amount0,
        uint256 _amount1
    ) internal pure returns (bool) {
        if (_amount0 == 0 && _amount1 == 0) revert BothTokenZero();

        // only token 1 no token 0
        if (_amount0 == 0) return false;

        // only token 0 no token 1
        if (_amount1 == 0) return true;

        uint256 thresholdAmount0 = FullMath.mulDiv(
            _state.rNum,
            _amount1,
            _state.rDen
        );
        return thresholdAmount0 < _amount0;
    }

    function _sanityCheckTickRange(
        address _pool,
        int24 _tickCurrent,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view {
        int24 tickSpacing = IUniswapV3Pool(_pool).tickSpacing();

        if (_tickLower % tickSpacing != 0) {
            revert InvalidTick(0, tickSpacing, _tickLower);
        }
        if (_tickUpper % tickSpacing != 0) {
            revert InvalidTick(0, tickSpacing, _tickUpper);
        }

        if (_tickCurrent < _tickLower) {
            revert InvalidTick(1, _tickCurrent, _tickLower);
        }
        if (_tickCurrent > _tickUpper) {
            revert InvalidTick(2, _tickCurrent, _tickUpper);
        }
    }

    function _uint256ToInt256(
        uint256 _num
    ) internal pure returns (int256 _out) {
        _out = int256(_num);
        if (uint256(_out) != _num) {
            revert Int256OverflowOrUnderflow(_num);
        }
    }

    function _slot0(
        address _pool
    ) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        // using low level call instead as we want to parse the data ourselves.
        // why do we do this? Because we want to support both uniswap and pancakeswap
        // uniswap.slot0.fee is uint8 but pancakeswap is u32
        (bool success, bytes memory data) = _pool.staticcall(
            abi.encodeWithSignature("slot0()")
        );
        require(success, "sf");

        (sqrtPriceX96, tick) = abi.decode(data, (uint160, int24));
    }
}
