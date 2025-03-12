// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibPercentageMath} from "../RateMath.sol";

// details about the uniswap position
struct Position {
    uint80 poolId;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
}

struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
}

/// @title Uniswap V3 Position Library
/// @notice Library for managing Uniswap V3 positions
library UniswapV3PositionLib {
    using SafeERC20 for IERC20;

    /// @dev Updates position's fee growth and tokens owed
    function updatePositionFeeGrowth(
        Position storage position,
        IUniswapV3Pool pool,
        uint128 positionLiquidity
    )
        internal
        returns (
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128
        )
    {
        bytes32 positionKey = PositionKey.compute(
            address(this),
            position.tickLower,
            position.tickUpper
        );

        (, feeGrowthInside0LastX128, feeGrowthInside1LastX128, , ) = pool
            .positions(positionKey);

        position.tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                positionLiquidity,
                FixedPoint128.Q128
            )
        );
        position.tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                positionLiquidity,
                FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    }

    /// @dev Creates a new position
    function createPosition(
        mapping(uint256 => Position) storage positions,
        uint256 tokenId,
        uint80 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128
    ) internal {
        positions[tokenId] = Position({
            poolId: poolId,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
    }

    /// @dev Calculate minimum amounts based on slippage rate
    function calculateMinAmounts(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint16 maxMintSlippageRate
    ) internal pure returns (uint256 amount0Min, uint256 amount1Min) {
        amount0Min =
            amount0Desired -
            LibPercentageMath.multiply(amount0Desired, maxMintSlippageRate);
        amount1Min =
            amount1Desired -
            LibPercentageMath.multiply(amount1Desired, maxMintSlippageRate);
    }

    /// @dev Calculate amount out minimum based on slippage
    function calculateAmountOutMinimum(
        uint256 target,
        uint256 reserve,
        uint16 slippage
    ) internal pure returns (uint256) {
        return ((target - reserve) * (1000 - slippage)) / 1000;
    }

    /// @dev Refund the extract amount not provided to the LP pool back to sender
    function refundExcess(
        address tokenAddress,
        uint256 amountExpected,
        uint256 amountActual,
        address recipient
    ) internal {
        if (amountExpected > amountActual) {
            IERC20(tokenAddress).forceApprove(address(this), 0);
            IERC20(tokenAddress).safeTransfer(
                recipient,
                amountExpected - amountActual
            );
        }
    }

    /// @dev Transfers funds to recipient
    function sendTokens(
        address recipient,
        address tokenAddress,
        uint256 amount
    ) internal {
        if (amount > 0) {
            IERC20(tokenAddress).safeTransfer(recipient, amount);
        }
    }

    /// @dev Transfers user funds into contract and approves for spending
    function transferAndApprove(
        address tokenAddress,
        uint256 amount,
        address sender,
        address spender
    ) internal {
        // transfer tokens to contract
        IERC20(tokenAddress).safeTransferFrom(sender, address(this), amount);

        // Approve the spender
        IERC20(tokenAddress).forceApprove(spender, amount);
    }

    /// @dev Approve token if needed
    function approveIfNeeded(
        address token,
        address spender,
        uint256 amount
    ) internal {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (allowance < amount) {
            IERC20(token).forceApprove(spender, amount);
        }
    }
}