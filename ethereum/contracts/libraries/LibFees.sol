// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct FeeEarned {
    uint256 fee0;
    uint256 fee1;
}

struct FeeEarnedTracker {
    mapping(address => FeeEarned) feeEarned;
}

library LibFeeEarnedTracker {
    function getFeeEarned(
        FeeEarnedTracker storage self,
        address _poolAddress
    ) internal view returns (uint256 fee0, uint256 fee1) {
        fee0 = self.feeEarned[_poolAddress].fee0;
        fee1 = self.feeEarned[_poolAddress].fee1;
    }

    function addFees(
        FeeEarnedTracker storage self,
        address _poolAddress,
        uint256 _fee0,
        uint256 _fee1
    ) internal {
        self.feeEarned[_poolAddress].fee0 += _fee0;
        self.feeEarned[_poolAddress].fee1 += _fee1;
    }
}
