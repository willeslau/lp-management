// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "./interfaces/IUniswapV3TokenPairs.sol";

error PoolNotExist();
error InvalidPool();
error InsufficientOutputAmount();
error UnsupportedTokenPair();

contract UniswapV3SwapPool is IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    address public immutable factory;
    IUniswapV3TokenPairs public tokenPairs;

    constructor(address _factory, address _tokenPairs) {
        factory = _factory;
        tokenPairs = IUniswapV3TokenPairs(_tokenPairs);
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        (address tokenIn, address tokenOut, uint24 poolFee) = abi.decode(
            data,
            (address, address, uint24)
        );

        address pool = IUniswapV3Factory(factory).getPool(tokenIn, tokenOut, poolFee);
        if (msg.sender != pool) {
            revert InvalidPool();
        }
        
        uint8 tokenPairId = tokenPairs.getTokenPairId(tokenIn, tokenOut);
        if (!tokenPairs.isSupportTokenPair(tokenPairId)) {
            revert UnsupportedTokenPair();
        }

        if (amount0Delta != 0) {
            _sendTo(tokenIn, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta != 0) {
            _sendTo(tokenIn, msg.sender, uint256(amount1Delta));
        }
    }

    /// @notice Swap tokens directly using UniswapV3Pool
    /// @param tokenPair Token pair information
    /// @param amountIn Input token amount
    /// @param amountOutMinimum Minimum output token amount
    /// @param isToken0ToToken1 Swap direction
    /// @return amountOut Actual output token amount
    function swap(
        TokenPair memory tokenPair,
        uint256 amountIn,
        uint256 amountOutMinimum,
        bool isToken0ToToken1
    ) external returns (uint256 amountOut) {
        address tokenIn = isToken0ToToken1
            ? tokenPair.token0
            : tokenPair.token1;
        address tokenOut = isToken0ToToken1
            ? tokenPair.token1
            : tokenPair.token0;

        address pool = IUniswapV3Factory(factory).getPool(
            tokenPair.token0,
            tokenPair.token1,
            tokenPair.poolFee
        );
        if (pool == address(0)) {
            revert PoolNotExist();
        }

        _approveIfNeeded(tokenIn, pool, amountIn);

        uint160 sqrtPriceLimitX96 = 0;

        bytes memory callbackData = abi.encode(
            tokenIn,
            tokenOut,
            tokenPair.poolFee
        );

        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            address(this),
            isToken0ToToken1,
            int256(amountIn),
            sqrtPriceLimitX96,
            callbackData
        );

        amountOut = uint256(-(isToken0ToToken1 ? amount1 : amount0));
        if (amountOut < amountOutMinimum) {
            revert InsufficientOutputAmount();
        }
    }

    /// @notice Check and approve token allowance
    /// @param token Token address
    /// @param spender Spender address
    /// @param amount Approval amount
    function _approveIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            IERC20(token).forceApprove(spender, amount);
        }
    }

    /// @notice Transfers funds to owner of NFT
    /// @param _recipient The recipient of the funds
    /// @param _tokenAddress The address of the token to send
    /// @param _amount The amount of token
    function _sendTo(
        address _recipient,
        address _tokenAddress,
        uint256 _amount
    ) internal {
        IERC20(_tokenAddress).safeTransfer(_recipient, _amount);
    }
}
