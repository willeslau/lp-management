// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library LibPercentageMath {
    function percentage100() internal pure returns(uint16) {
        return 1000;
    } 

    function multiply(
        uint256 num,
        uint16 rate
    ) internal pure returns (uint256) {
        return (num * uint256(rate)) / 1000;
    }

    function multiplyU128(
        uint128 num,
        uint16 rate
    ) internal pure returns (uint128) {
        return (num * uint128(rate)) / 1000;
    }
}
