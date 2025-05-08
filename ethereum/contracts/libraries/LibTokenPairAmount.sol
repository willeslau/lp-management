// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct TokenPairAmount {
    uint256 amount0;
    uint256 amount1;
}

struct TokenPairAmountTracker {
    /// @notice Each token pair amounts
    mapping(uint8 => TokenPairAmount) tokenPairAmounts;
}

library LibTokenPairAmountTracker {
    function getAmounts(
        TokenPairAmountTracker storage self,
        uint8 _tokenPairId
    ) internal view returns (uint256 a0, uint256 a1) {
        a0 = self.tokenPairAmounts[_tokenPairId].amount0;
        a1 = self.tokenPairAmounts[_tokenPairId].amount1;
    }

    function changeAmounts(
        TokenPairAmountTracker storage self,
        uint8 _tokenPairId,
        int256 _amount0,
        int256 _amount1
    ) internal {
        self.tokenPairAmounts[_tokenPairId].amount0 = _add(
            self.tokenPairAmounts[_tokenPairId].amount0,
            _amount0
        );
        self.tokenPairAmounts[_tokenPairId].amount1 = _add(
            self.tokenPairAmounts[_tokenPairId].amount1,
            _amount1
        );
    }

    function changeAmounts(
        TokenPairAmountTracker storage self,
        uint8 _tokenPairId,
        int128 _amount0,
        int128 _amount1
    ) internal {
        self.tokenPairAmounts[_tokenPairId].amount0 = _addI128(
            self.tokenPairAmounts[_tokenPairId].amount0,
            _amount0
        );
        self.tokenPairAmounts[_tokenPairId].amount1 = _addI128(
            self.tokenPairAmounts[_tokenPairId].amount1,
            _amount1
        );
    }

    function changeAmounts(
        TokenPairAmountTracker storage self,
        uint8 _tokenPairId,
        uint128 _amount0,
        uint128 _amount1
    ) internal {
        self.tokenPairAmounts[_tokenPairId].amount0 += _amount0;
        self.tokenPairAmounts[_tokenPairId].amount1 += _amount1;
    }

    function setAmounts(
        TokenPairAmountTracker storage self,
        uint8 _tokenPairId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        self.tokenPairAmounts[_tokenPairId].amount0 = _amount0;
        self.tokenPairAmounts[_tokenPairId].amount1 = _amount1;
    }

    function _addI128(uint256 _x, int128 _y) internal pure returns (uint256) {
        if (_y > 0) return _x + uint256(int256(_y));
        if (_y < 0) return _x - uint256(int256(-_y));
        return _x;
    }

    function _add(uint256 _x, int256 _y) internal pure returns (uint256) {
        if (_y > 0) return _x + uint256(_y);
        if (_y < 0) return _x - uint256(-_y);
        return _x;
    }
}
