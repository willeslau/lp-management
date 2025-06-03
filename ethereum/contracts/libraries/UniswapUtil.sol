// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {PositionKey} from "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

contract UniswapUtil {
    function getFeeGrowthInside(
        address _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) external view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        (, int24 tickCurrent ) = slot0(_pool);

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        (, , uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128, , , , ) = pool.ticks(_tickLower);
        (, , uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128, , , , ) = pool.ticks(_tickUpper);

        if (tickCurrent < _tickLower) {
            feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
            feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
        } else if (tickCurrent < _tickUpper) {
            uint256 feeGrowthGlobal0X128 = pool.feeGrowthGlobal0X128();
            uint256 feeGrowthGlobal1X128 = pool.feeGrowthGlobal1X128();
            feeGrowthInside0X128 = feeGrowthGlobal0X128 - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
            feeGrowthInside1X128 = feeGrowthGlobal1X128 - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
        } else {
            feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
            feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
        }
    }

    function slot0s(
        address[] calldata _pools
    ) public view returns (uint160[] memory sqrtPriceX96s) {
        sqrtPriceX96s = new uint160[](_pools.length);

        for (uint256 i = 0; i < _pools.length; ) {
            (sqrtPriceX96s[i], ) =  slot0(_pools[i]);

            unchecked {
                i++;
            }
        }
    }

    function slot0(
        address _pool
    ) public view returns (uint160 sqrtPriceX96, int24 tick) {
        // using low level call instead as we want to parse the data ourselves.
        // why do we do this? Because we want to support both uniswap and pancakeswap
        // uniswap.slot0.fee is uint8 but pancakeswap is u32
        (bool success, bytes memory data) = _pool.staticcall(
            abi.encodeWithSignature("slot0()")
        );
        require(success, "sf");

        (sqrtPriceX96, tick) = abi.decode(data, (uint160, int24));
    }

    function position(
        address _pool,
        address _owner,
        int24 _tickLower,
        int24 _tickUpper
    )
        external
        view
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        bytes32 uniswapPositionKey = PositionKey.compute(
            _owner,
            _tickLower,
            _tickUpper
        );

        (liquidity, , , tokensOwed0, tokensOwed1) = IUniswapV3Pool(_pool)
            .positions(uniswapPositionKey);

        (uint160 sqrtPriceX96, ) = slot0(_pool);

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(_tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(_tickUpper);

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidity
        );
    }
}
