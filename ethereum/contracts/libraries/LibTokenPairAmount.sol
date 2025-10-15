// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct TokenPairAmount {
    uint256 amount0;
    uint256 amount1;
}

library LibTokenPairAmount {
    function merge(
        TokenPairAmount memory self,
        TokenPairAmount memory other
    ) internal pure {
        self.amount0 += other.amount0;
        self.amount1 += other.amount1;
    }

    function deduct(
        TokenPairAmount memory self,
        TokenPairAmount memory other
    ) internal pure {
        self.amount0 -= other.amount0;
        self.amount1 -= other.amount1;
    }

    function add(
        TokenPairAmount memory self,
        int256 _amount0,
        int256 _amount1
    ) internal pure {
        self.amount0 = _add(self.amount0, _amount0);
        self.amount1 = _add(self.amount1, _amount1);
    }

    function _add(
        uint256 _amount,
        int256 _change
    ) internal pure returns (uint256) {
        if (_change > 0) {
            return _amount + uint256(_change);
        } else {
            return _amount - uint256(-_change);
        }
    }
}
