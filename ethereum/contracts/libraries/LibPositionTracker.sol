// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// details about the uniswap position
struct Position {
    uint8 tokenPairId;
    int24 tickLower;
    int24 tickUpper;
}

struct PositionTracker {
    /// @dev The token ID position data
    mapping(bytes32 => Position) positions;
    /// @notice The list of currently open positions
    EnumerableSet.Bytes32Set positionKeys;
}

library LibPositionTracker {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error PostionAlreadyExists(int24 lower, int24 upper);
    error InvalidPositionKey(bytes32 key);
    error PositionNotCleared();

    function exists(
        PositionTracker storage self,
        uint8 _tokenPairId,
        int24 _tickLower,
        int24 _tickUpper
    ) internal view returns (bool, bytes32) {
        bytes32 positionKey = _derivePositionKey(
            _tokenPairId,
            _tickLower,
            _tickUpper
        );
        return (self.positionKeys.contains(positionKey), positionKey);
    }

    function tryInsertNewPositionKey(
        PositionTracker storage self,
        uint8 _tokenPairId,
        int24 _tickLower,
        int24 _tickUpper
    ) internal returns (bytes32 positionKey) {
        positionKey = _derivePositionKey(_tokenPairId, _tickLower, _tickUpper);

        if (self.positionKeys.contains(positionKey)) {
            revert PostionAlreadyExists(_tickLower, _tickUpper);
        }
        self.positionKeys.add(positionKey);
    }

    function remove(
        PositionTracker storage self,
        bytes32 _positionKey
    ) internal {
        Position storage position = self.positions[_positionKey];
        if (position.tokenPairId == 0) revert PositionNotCleared();
        delete self.positions[_positionKey];
    }

    function setPositionKeyData(
        PositionTracker storage self,
        bytes32 _positionKey,
        uint8 _tokenPairId,
        int24 _tickLower,
        int24 _tickUpper
    ) internal {
        self.positions[_positionKey] = Position({
            tokenPairId: _tokenPairId,
            tickLower: _tickLower,
            tickUpper: _tickUpper
        });
    }

    function getPositionTokenPair(
        PositionTracker storage self,
        bytes32 _positionKey
    ) internal view returns (uint8 tokenPairId) {
        tokenPairId = self.positions[_positionKey].tokenPairId;
        if (tokenPairId == 0) {
            revert InvalidPositionKey(_positionKey);
        }
    }

    function getPositionTicks(
        PositionTracker storage self,
        bytes32 _positionKey
    ) internal view returns (int24 lower, int24 uppper) {
        return (
            self.positions[_positionKey].tickLower,
            self.positions[_positionKey].tickUpper
        );
    }

    function _derivePositionKey(
        uint8 _tokenPairId,
        int24 _tickLower,
        int24 _tickUpper
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked(_tokenPairId, _tickLower, _tickUpper));
    }
}
