// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {UniswapV3LpManagerV3} from "../manager/UniswapV3LpManagerV3.sol";

contract UniswapV3LpManagerV3Test is UniswapV3LpManagerV3 {
    // dummy initializer for test deployment
    function initialize2() external initializer {
        __Ownable_init();
    }

    function floorTick(
        int24 targetTick,
        int24 tickSpacing
    ) external pure returns (int24) {
        return _floorTick(targetTick, tickSpacing);
    }

    function ceilTick(
        int24 targetTick,
        int24 tickSpacing
    ) external pure returns (int24) {
        return _ceilTick(targetTick, tickSpacing);
    }

    function skewedLowerRange(
        int24 targetLowerTick,
        int24 curTick,
        int24 tickSpacing
    ) external pure returns (int24 lower, int24 upper) {
        return _skewedLowerRange(targetLowerTick, curTick, tickSpacing);
    }

    function skewedUpperRange(
        int24 targetUpperTick,
        int24 curTick,
        int24 tickSpacing
    ) external pure returns (int24 lower, int24 upper) {
        return _skewedUpperRange(targetUpperTick, curTick, tickSpacing);
    }
}
