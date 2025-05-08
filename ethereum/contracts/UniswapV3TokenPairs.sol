// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3TokenPairs, TokenPair, TokenPairAdresses} from "./interfaces/IUniswapV3TokenPairs.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    TokenAddressesNotSorted,
    PairAlreadyExists,
    InvalidPoolAddress,
    InvalidTokenAddress,
    TokenPairNotExits
} from "./Errors.sol";

contract UniswapV3TokenPairs is IUniswapV3TokenPairs, Ownable {


    event TokenPairAdded(
        uint8 indexed pairId,
        address indexed token0,
        address indexed token1,
        address pool,
        uint24 poolFee
    );

    mapping(uint256 => TokenPair) private _tokenPairs;
    mapping(bytes32 => uint8) private _pairIds;

    uint8 private _nextPairId = 1;

    function getTokenPairAddress(
        uint8 _id
    ) external view returns (TokenPairAdresses memory) {
        TokenPair storage pair = _tokenPairs[_id];

        if (pair.id == 0) {
            revert TokenPairNotExits(pair.id);
        }

        return
            TokenPairAdresses({
                pool: pair.pool,
                token0: pair.token0,
                token1: pair.token1
            });
    }

    function getTokenPairPool(uint8 _id) external view returns (address pool) {
        pool = _tokenPairs[_id].pool;
        if (pool == address(0)) revert TokenPairNotExits(_id);
    }

    function addTokenPair(
        address pool,
        address token0,
        address token1,
        uint24 poolFee
    ) external onlyOwner returns (uint256) {
        bytes32 key = _validateTokenPair(pool, token0, token1, poolFee);

        uint8 pairId = _nextPairId++;
        _tokenPairs[pairId] = TokenPair({
            id: pairId,
            pool: pool,
            token0: token0,
            token1: token1,
            poolFee: poolFee
        });

        _pairIds[key] = pairId;

        emit TokenPairAdded(pairId, token0, token1, pool, poolFee);

        return pairId;
    }

    function getTokenPairId(
        address token0,
        address token1,
        uint24 poolFee
    ) external view returns (uint8) {
        (token0, token1) = _sortTokens(token0, token1);
        bytes32 key = _pairIdKey(token0, token1, poolFee);
        return _pairIds[key];
    }

    function isTokenPairSupported(
        address token0,
        address token1,
        uint24 poolFee
    ) external view returns (bool) {
        (token0, token1) = _sortTokens(token0, token1);
        bytes32 key = _pairIdKey(token0, token1, poolFee);
        return _pairIds[key] > 0;
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
    ) public view override returns (TokenPair memory pair) {
        pair = _tokenPairs[_id];

        if (pair.id == 0) {
            revert TokenPairNotExits(pair.id);
        }
    }

    function getTokenPairAddresses(
        uint8 _id
    ) external view override returns (address, address) {
        TokenPair memory pair = getTokenPair(_id);
        return (pair.token0, pair.token1);
    }

    function isSupportTokenPair(uint8 _id) public view override returns (bool) {
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
        address token1,
        uint24 poolFee
    ) internal view returns (bytes32) {
        if (pool == address(0)) {
            revert InvalidPoolAddress();
        }

        if (token0 == address(0) || token1 == address(0)) {
            revert InvalidTokenAddress();
        }

        if (token0 >= token1) {
            revert TokenAddressesNotSorted();
        }

        bytes32 key = _pairIdKey(token0, token1, poolFee);
        if (_pairIds[key] != 0) {
            revert PairAlreadyExists();
        }

        return key;
    }

    function _pairIdKey(
        address token0,
        address token1,
        uint24 poolFee
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token0, token1, poolFee));
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
