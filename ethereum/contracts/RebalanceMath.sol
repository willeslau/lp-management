// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import "hardhat/console.sol";

contract RebalanceMath {
    uint160 constant public BASE = 100000;

    function _nearestUsableTick(int24 _tick, int24 _tickSpacing) internal pure returns(int24 resTick) {
        resTick = _tick / _tickSpacing * _tickSpacing;

        if (resTick < TickMath.MIN_TICK) resTick += _tickSpacing;
        else if (resTick > TickMath.MAX_TICK) resTick -= _tickSpacing;
    }

    function _deriveTickRange(
        uint160 _rangeUpperSqrt,
        uint160 _rangeLowerSqrt,
        uint160 _sqrtCurrent,
        int24 _tickSpacing
    ) internal pure returns (int24 tickLower, int24 tickUpper) {
        uint160 upperSqrt = _sqrtCurrent * _rangeUpperSqrt / BASE;
        uint160 lowerSqrt = _sqrtCurrent * _rangeLowerSqrt / BASE;

        tickUpper = TickMath.getTickAtSqrtRatio(upperSqrt);
        tickLower = TickMath.getTickAtSqrtRatio(lowerSqrt);

        tickUpper = _nearestUsableTick(tickUpper, _tickSpacing);
        tickLower = _nearestUsableTick(tickLower, _tickSpacing);
    }
}
