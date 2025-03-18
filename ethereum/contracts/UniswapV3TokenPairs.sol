// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3TokenPairs, TokenPair} from "./interfaces/IUniswapV3TokenPairs.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract UniswapV3TokenPairs is IUniswapV3TokenPairs, Ownable {
    mapping(uint256 => TokenPair) private _tokenPairs;
    mapping(address => mapping(address => uint8)) private _pairIds;
    uint8 private _nextPairId = 1;

    error TokenAddressesNotSorted();
    error PairAlreadyExists();
    error InvalidPoolAddress();
    error InvalidTokenAddress();
    error InvalidPairId();

    event TokenPairAdded(
        uint8 indexed pairId,
        address indexed token0,
        address indexed token1,
        address pool,
        uint24 poolFee
    );

    function addTokenPair(
        address pool,
        address token0,
        address token1,
        uint24 poolFee
    ) external onlyOwner returns (uint256) {
        _validateTokenPair(pool, token0, token1);

        uint8 pairId = _nextPairId++;
        _tokenPairs[pairId] = TokenPair({
            id: pairId,
            pool: pool,
            token0: token0,
            token1: token1,
            poolFee: poolFee
        });

        _pairIds[token0][token1] = pairId;

        emit TokenPairAdded(pairId, token0, token1, pool, poolFee);

        return pairId;
    }

    function getTokenPairId(
        address token0,
        address token1
    ) external view returns (uint8) {
        (token0, token1) = _sortTokens(token0, token1);
        return _pairIds[token0][token1];
    }

    function isTokenPairSupported(
        address token0,
        address token1
    ) external view returns (bool) {
        (token0, token1) = _sortTokens(token0, token1);
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
    ) external view override returns (TokenPair memory) {
        return _tokenPairs[_id];
    }

    function getTokenPairAddresses(
        uint8 _id
    ) external view override returns (address, address) {
        TokenPair memory pair = _tokenPairs[_id];
        return (pair.token0, pair.token1);
    }

    function isSupportTokenPair(
        uint8 _id
    ) external view override returns (bool) {
        return _id > 0 && _id < _nextPairId;
    }

    // @dev: Support pool address validation
    // @notice: TODO - Add pool address validation logic to verify:
    // 1. Pool exists on Uniswap V3
    // 2. Pool matches the token pair and fee
    // 3. Pool is initialized and active
    function _validateTokenPair(
        address pool,
        address token0,
        address token1
    ) internal view {
        if (pool == address(0)) {
            revert InvalidPoolAddress();
        }

        if (token0 == address(0) || token1 == address(0)) {
            revert InvalidTokenAddress();
        }

        if (token0 >= token1) {
            revert TokenAddressesNotSorted();
        }

        if (_pairIds[token0][token1] != 0) {
            revert PairAlreadyExists();
        }
    }

    function _sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA > tokenB) {
            return (tokenB, tokenA);
        }
        return (tokenA, tokenB);
    }
}
