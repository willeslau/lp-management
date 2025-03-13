// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IUniswapV3TokenPairs.sol";

contract MockUniswapV3TokenPairs is IUniswapV3TokenPairs {
    mapping(uint256 => TokenPair) private _tokenPairs;
    mapping(address => mapping(address => uint8)) private _pairIds;
    uint8 private _nextPairId = 1;

    function addTokenPair(
        address pool,
        address token0,
        address token1,
        uint24 poolFee
    ) external returns (uint256) {
        require(token0 < token1, "Token addresses must be sorted");
        require(_pairIds[token0][token1] == 0, "Pair already exists");

        uint8 pairId = _nextPairId++;
        _tokenPairs[pairId] = TokenPair({
            id: pairId,
            pool: pool,
            token0: token0,
            token1: token1,
            poolFee: poolFee
        });

        _pairIds[token0][token1] = pairId;

        return pairId;
    }

    function getTokenPair(
        uint256 pairId
    ) external view returns (TokenPair memory) {
        return _tokenPairs[pairId];
    }

    function getTokenPairId(
        address token0,
        address token1
    ) external view returns (uint8) {
        // Ensure token0 < token1 for consistent mapping
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        return _pairIds[token0][token1];
    }

    function isTokenPairSupported(
        address token0,
        address token1
    ) external view returns (bool) {
        // Ensure token0 < token1 for consistent mapping
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        return _pairIds[token0][token1] > 0;
    }

    function getAllTokenPairs() external view returns (TokenPair[] memory) {
        uint256 count = _nextPairId - 1;
        TokenPair[] memory pairs = new TokenPair[](count);

        for (uint256 i = 1; i <= count; i++) {
            pairs[i - 1] = _tokenPairs[i];
        }

        return pairs;
    }

    function getTokenPair(
        uint8 _id
    ) external override returns (TokenPair memory) {
        return _tokenPairs[_id];
    }

    function getTokenPairAddresses(
        uint8 _id
    ) external override returns (address, address) {
        TokenPair memory pair = _tokenPairs[_id];
        return (pair.token0, pair.token1);
    }

    function isSupportTokenPair(uint8 _id) external override returns (bool) {
        return _id > 0 && _id < _nextPairId;
    }
}
