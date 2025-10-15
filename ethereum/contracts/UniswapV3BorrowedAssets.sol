// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TokenPairAmount, LibTokenPairAmount} from "./libraries/LibTokenPairAmount.sol";

import {IRebalanceSwapMath, QuoteParams} from "./RebalanceSwapMath.sol";
import {ISwapUtil, SwapParams, Swapper} from "./SwapUtil.sol";

import {UniswapV3Operations, PoolMetadata} from "./UniswapV3Operations.sol";
import {RebalanceMath} from "./RebalanceMath.sol";

contract UniswapV3BorrowedAssets is UniswapV3Operations, OwnableUpgradeable, UUPSUpgradeable {
    function getLendingPosition() external view {}

    function getLPPosition() external view {}

    function enableCollateral() external onlyOwner() {}

    function provideCollateral() external onlyOwner() {}

    function openPosition() external onlyOwner {}

    function borrowAndOpenPosition() external onlyOwner {}

    function closePosition() external onlyOwner {}

    function repay() external onlyOwner {}

    function _authorizeUpgrade(address) internal view override onlyOwner {}
}

// library LibPoolAddresses {
//     function balance0(
//         PoolAddresses memory self,
//         address _who
//     ) internal view returns (uint256) {
//         return IERC20(self.token0).balanceOf(_who);
//     }

//     function balance1(
//         PoolAddresses memory self,
//         address _who
//     ) internal view returns (uint256) {
//         return IERC20(self.token1).balanceOf(_who);
//     }
// }

// abstract contract UniswapV3SingleSide {
// //     using SafeERC20 for IERC20;
// //     using LibPoolAddresses for PoolAddresses;

// //     uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;
// //     uint160 constant RANGE_DENOMINATOR = 100000;

// //     mapping(address => Position) public positions;

// //     event PositionOpen(
// //         address pool,
// //         int24 tickLower,
// //         uint160 priceSqrt,
// //         int24 tickUpper,
// //         uint256 amount0,
// //         uint256 amount1
// //     );
// //     event PostionClosed(
// //         address pool,
// //         int24 tickLower,
// //         int24 tickUpper,
// //         uint128 amount0,
// //         uint128 amount1
// //     );

// //     error StillInRange();

// //     // ==================== Internal Methods ====================
// //     function isPositionInRange(
// //         address _pool,
// //         Position memory _position
// //     ) internal view returns (bool) {
// //         (, int24 currentTick) = _slot0(_pool);
// //         return
// //             _position.tickLower <= currentTick &&
// //             currentTick <= _position.tickUpper;
// //     }

// //     function processCurrentPosition(
// //         address _pool,
// //         Position memory _position,
// //         uint160 _rangeNumerator
// //     ) internal {
// //         (, int24 currentTick) = _slot0(_pool);
// //         if (
// //             _position.tickLower <= currentTick &&
// //             currentTick <= _position.tickUpper
// //         ) {
// //             revert StillInRange();
// //         }

// //         _closePosition(_pool, _position);
// //         _createPosition(_pool, _rangeNumerator);
// //     }

//     function getPoolAddresses(
//         address _pool
//     ) internal view returns (address token0, address token1) {
//         token0 = IUniswapV3Pool(_pool).token0();
//         token1 = IUniswapV3Pool(_pool).token1();
//     }

//     function _createPosition(address _pool, uint160 _rangeNumerator) internal {
//         (address token0, address token1) = getPoolAddresses(_pool);

//         uint256 token0Balance = IERC20(token0).balanceOf(_who);
//         uint256 token1Balance = IERC20(token1).balanceOf(_who);

//         if (token0Balance == 0) {
//             return
//                 addPositionToken1(
//                     _pool,
//                     token0,
//                     token1,
//                     token1Balance,
//                     _rangeNumerator
//                 );
//         }
//         if (token1Balance == 0) {
//             return
//                 addPositionToken0(
//                     _pool,
//                     token0,
//                     token1,
//                     token0Balance,
//                     _rangeNumerator
//                 );
//         } else {
//             revert("Not supported now");
//         }
//     }

// //     function _floorTick(
// //         int24 _targetTick,
// //         int24 _tickSpacing
// //     ) internal pure returns (int24) {
// //         int24 remainder = _targetTick % _tickSpacing;
// //         if (remainder == 0) return _targetTick;

// //         if (_targetTick > 0) return _targetTick - remainder;

// //         // solidity handling remainder of negative number is sign * (abs(num) % v)
// //         return _targetTick - remainder - _tickSpacing;
// //     }

// //     function _ceilTick(
// //         int24 _targetTick,
// //         int24 _tickSpacing
// //     ) internal pure returns (int24) {
// //         int24 remainder = _targetTick % _tickSpacing;
// //         if (remainder == 0) return _targetTick;

// //         // if (_targetTick > 0) return
// //         // solidity handling remainder of negative number is sign * (abs(num) % v)
// //         return _targetTick - remainder;
// //     }

// //     /// @dev This means the lower and upper ticks are below the current tick. Caller should make sure
// //     ///      targetLowerTick is smaller than curTick
// //     function _skewedLowerRange(
// //         int24 targetLowerTick,
// //         int24 curTick,
// //         int24 tickSpacing
// //     ) internal pure returns (int24 lower, int24 upper) {
// //         // we shift lower tick further away from current tick to be more conservative in the tick range
// //         lower = _floorTick(targetLowerTick, tickSpacing);
// //         upper = _floorTick(curTick - 1, tickSpacing);
// //     }

// //     /// @dev This means the lower and upper ticks are above the current tick. Caller should make sure
// //     ///      targetUpperTick is smaller than curTick
// //     function _skewedUpperRange(
// //         int24 targetUpperTick,
// //         int24 curTick,
// //         int24 tickSpacing
// //     ) internal pure returns (int24 lower, int24 upper) {
// //         // we shift upper tick further away from current tick to be more conservative in the tick range
// //         upper = _ceilTick(targetUpperTick, tickSpacing);
// //         lower = _ceilTick(curTick + 1, tickSpacing);
// //     }

// //     function addPositionToken1(
// //         address _pool,
// //         PoolAddresses memory _addresses,
// //         uint256 amount1,
// //         uint160 _rangeNumerator
// //     ) internal {
// //         (uint160 priceSqrt, int24 currentTick) = _slot0(_pool);

// //         uint160 priceSqrtLower = ((RANGE_DENOMINATOR - _rangeNumerator) *
// //             priceSqrt) / RANGE_DENOMINATOR;
// //         (int24 tickLower, int24 tickUpper) = _skewedLowerRange(
// //             TickMath.getTickAtSqrtRatio(priceSqrtLower),
// //             currentTick,
// //             IUniswapV3Pool(_pool).tickSpacing()
// //         );

// //         LiquidityChangeOutput memory output = _addLiquidity(
// //             _pool,
// //             _addresses,
// //             tickLower,
// //             priceSqrt,
// //             tickUpper,
// //             0,
// //             amount1
// //         );

// //         positions[_pool].tickLower = tickLower;
// //         positions[_pool].tickUpper = tickUpper;
// //         positions[_pool].liquidity = output.liquidity;

// //         emit PositionOpen(
// //             _pool,
// //             tickLower,
// //             priceSqrt,
// //             tickUpper,
// //             output.amount0,
// //             output.amount1
// //         );
// //     }

//     function _addPositionToken0(
//         address _pool,
//         address ,
//         uint256 amount0,
//         uint160 _rangeNumerator
//     ) internal {
//         (uint160 priceSqrt, int24 currentTick) = _slot0(_pool);

//         uint160 priceSqrtUpper = ((RANGE_DENOMINATOR + _rangeNumerator) *
//             priceSqrt) / RANGE_DENOMINATOR;
//         (int24 tickLower, int24 tickUpper) = _skewedUpperRange(
//             TickMath.getTickAtSqrtRatio(priceSqrtUpper),
//             currentTick,
//             IUniswapV3Pool(_pool).tickSpacing()
//         );

//         LiquidityChangeOutput memory output = _addLiquidity(
//             _pool,
//             _addresses,
//             tickLower,
//             priceSqrt,
//             tickUpper,
//             amount0,
//             0
//         );

//         positions[_pool].tickLower = tickLower;
//         positions[_pool].tickUpper = tickUpper;
//         positions[_pool].liquidity = output.liquidity;

//         emit PositionOpen(
//             _pool,
//             tickLower,
//             priceSqrt,
//             tickUpper,
//             output.amount0,
//             output.amount1
//         );
//     }
// }
