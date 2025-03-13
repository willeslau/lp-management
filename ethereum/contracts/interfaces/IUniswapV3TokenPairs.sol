// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice The token pair on uniswap
struct TokenPair {
    uint8 id;
    address pool;
    address token0;
    address token1;
    uint24 poolFee;
}

library LibTokenId {
    function isValidTokenPairId(uint8 _id) internal pure returns (bool) {
        return _id != 0;
    }
}

// TODO: implement the interface

interface IUniswapV3TokenPairs {
    /// @dev returns the full token pair information by id
    function getTokenPair(uint8 _id) external returns (TokenPair memory);

    function getTokenPairId(
        address _token0,
        address _token1
    ) external returns (uint8);

    function getTokenPairAddresses(
        uint8 _id
    ) external returns (address, address);

    /// @dev returns false if the token pair id is not supported
    function isSupportTokenPair(uint8 _id) external returns (bool);
}
