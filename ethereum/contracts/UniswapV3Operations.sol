// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPairAmount, LibTokenPairAmount} from "./libraries/LibTokenPairAmount.sol";

import {IRebalanceSwapMath, QuoteParams} from "./RebalanceSwapMath.sol";
import {ISwapUtil, SwapParams, Swapper} from "./SwapUtil.sol";

struct PoolMetadata {
    uint24 poolFee;
    address token0;
    address token1;
}

contract UniswapV3Operations {
    using SafeERC20 for IERC20;
    using LibTokenPairAmount for TokenPairAmount;

    INonfungiblePositionManager public manager;
    ISwapUtil public swapUtil;
    IRebalanceSwapMath public swapMath;

    error InvalidAmountToU128(uint256 amount);

    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    function _getPosition(
        uint256 _tokenId
    ) internal view returns (Position memory position) {
        if (_tokenId == 0) {
            return position;
        }

        (
            ,
            ,
            ,
            ,
            ,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            ,

        ) = manager.positions(_tokenId);
    }

    function _mint(
        PoolMetadata memory _tokenPair,
        int24 _tickLower,
        int24 _tickUpper,
        TokenPairAmount memory _amounts,
        uint256 _deadline
    )
        internal
        returns (uint256 id, uint256 amount0, uint256 amount1)
    {
        IERC20(_tokenPair.token0).approve(address(manager), _amounts.amount0);
        IERC20(_tokenPair.token1).approve(address(manager), _amounts.amount1);

        (id, , amount0, amount1) = manager.mint(
            INonfungiblePositionManager.MintParams({
                token0: _tokenPair.token0,
                token1: _tokenPair.token1,
                fee: _tokenPair.poolFee,
                tickLower: _tickLower,
                tickUpper: _tickUpper,
                amount0Desired: _amounts.amount0,
                amount1Desired: _amounts.amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: _deadline
            })
        );
    }

    function _close(
        uint256 _id,
        address _recipient,
        uint256 _deadline
    ) internal returns (TokenPairAmount memory amounts) {
        (, , , , , , , uint128 liquidity, , , , ) = manager.positions(_id);

        manager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: _id,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: _deadline
            })
        );

        (amounts.amount0, amounts.amount1) = manager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: _id,
                recipient: _recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        manager.burn(_id);
    }

    function _toU128(uint256 _num) internal pure returns (uint128 v) {
        v = uint128(_num);
        if (uint256(v) != _num) {
            revert InvalidAmountToU128(_num);
        }
    }

    function _swap(
        QuoteParams calldata _quote,
        address _pool,
        PoolMetadata memory _tokenPair,
        TokenPairAmount memory _amounts,
        int24 _tickLower,
        int24 _tickUpper
    ) internal returns (TokenPairAmount memory) {
        (int256 amount0, int256 amount1, int256 minAmountOut) = swapMath
            .calculateSwapState(
                _pool,
                _quote,
                _tickLower,
                _tickUpper,
                _amounts.amount0,
                _amounts.amount1
            );

        int256 swapped0;
        int256 swapped1;

        if (_quote.zeroForOne) {
            IERC20(_tokenPair.token0).approve(
                address(swapUtil),
                uint256(amount0)
            );
            (swapped0, swapped1) = swapUtil.swap(
                _pool,
                _tokenPair.token0,
                SwapParams({
                    swapper: Swapper.UniswapPool,
                    zeroForOne: true,
                    priceSqrtX96Limit: _quote.priceLimitSqrt,
                    amountOutMin: minAmountOut,
                    amountIn: amount0
                })
            );
        } else {
            IERC20(_tokenPair.token1).approve(
                address(swapUtil),
                uint256(amount1)
            );
            (swapped0, swapped1) = swapUtil.swap(
                _pool,
                _tokenPair.token1,
                SwapParams({
                    swapper: Swapper.UniswapPool,
                    zeroForOne: false,
                    priceSqrtX96Limit: _quote.priceLimitSqrt,
                    amountOutMin: minAmountOut,
                    amountIn: amount1
                })
            );
        }

        _amounts.add(swapped0, swapped1);

        return _amounts;
    }
}
