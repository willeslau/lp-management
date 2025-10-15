// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

// import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import {UniswapV3LpManagerAdmin} from "./UniswapV3LpManagerAdmin.sol";
// import {LiquidityChangeOutput} from "../interfaces/IUniswapV3PoolProxy.sol";
// import {UniswapV3PoolsUtilV2, PoolAddresses, Position} from "../UniswapV3PoolsUtilV2.sol";

// import {ISwapUtil} from "../SwapUtil.sol";

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

// /// @title Uniswap V3 LP Manager
// /// @notice Manages Uniswap V3 liquidity positions
// contract UniswapV3LpManagerV3 is
//     UUPSUpgradeable,
//     UniswapV3PoolsUtilV2,
//     UniswapV3LpManagerAdmin
// {
//     using SafeERC20 for IERC20;
//     using LibPoolAddresses for PoolAddresses;

//     uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;
//     uint160 constant RANGE_DENOMINATOR = 100000;

//     mapping(address => Position) public positions;

//     event PositionOpen(
//         address pool,
//         int24 tickLower,
//         uint160 priceSqrt,
//         int24 tickUpper,
//         uint256 amount0,
//         uint256 amount1
//     );
//     event PostionClosed(
//         address pool,
//         int24 tickLower,
//         int24 tickUpper,
//         uint128 amount0,
//         uint128 amount1
//     );

//     error StillInRange();

//     /// @custom:oz-upgrades-unsafe-allow constructor
//     constructor() {
//         _disableInitializers();
//     }

//     function initialize(
//         address _liquidityOwner,
//         address _balancer
//     ) external initializer {
//         __Ownable_init();

//         liquidityOwner = _liquidityOwner;
//         balancer = _balancer;
//     }

//     function getPoolPositionInfo(
//         address _pool
//     ) external view returns (Position memory pos, bool inRange) {
//         pos = positions[_pool];
//         inRange = isPositionInRange(_pool, pos);
//     }

//     function rebalance(
//         address _pool,
//         uint160 _rangeNumerator
//     ) external onlyAddress(balancer) {
//         Position memory position = positions[_pool];
//         if (position.liquidity == 0) {
//             _createPosition(_pool, _rangeNumerator);
//         } else {
//             processCurrentPosition(_pool, position, _rangeNumerator);
//         }
//     }

//     function closePosition(
//         address _pool,
//         Position memory _position
//     ) public onlyAddress(balancer) {
//         _closePosition(_pool, _position);
//     }

//     function withdraw(address _token) external onlyOwner {
//         uint256 balance = IERC20(_token).balanceOf(address(this));
//         IERC20(_token).transfer(liquidityOwner, balance);
//     }

//     function withdraw(address _token, uint256 _amount) external onlyOwner {
//         IERC20(_token).transfer(liquidityOwner, _amount);
//     }

//     // ==================== Internal Methods ====================
//     function _closePosition(
//         address _pool,
//         Position memory _position
//     ) internal returns (uint128 amount0Collected, uint128 amount1Collected) {
//         IUniswapV3Pool pool = IUniswapV3Pool(_pool);

//         _burnAll(pool, _position);

//         // do not withdraw the fee, compound it
//         (amount0Collected, amount1Collected) = _collect(
//             pool,
//             address(this),
//             _position,
//             UINT128_MAX,
//             UINT128_MAX
//         );

//         delete positions[_pool];

//         emit PostionClosed(
//             _pool,
//             _position.tickLower,
//             _position.tickUpper,
//             amount0Collected,
//             amount1Collected
//         );
//     }

//     function isPositionInRange(
//         address _pool,
//         Position memory _position
//     ) internal view returns (bool) {
//         (, int24 currentTick) = _slot0(_pool);
//         return
//             _position.tickLower <= currentTick &&
//             currentTick <= _position.tickUpper;
//     }

//     function processCurrentPosition(
//         address _pool,
//         Position memory _position,
//         uint160 _rangeNumerator
//     ) internal {
//         (, int24 currentTick) = _slot0(_pool);
//         if (
//             _position.tickLower <= currentTick &&
//             currentTick <= _position.tickUpper
//         ) {
//             revert StillInRange();
//         }

//         _closePosition(_pool, _position);
//         _createPosition(_pool, _rangeNumerator);
//     }

//     function getPoolAddresses(
//         address _pool
//     ) internal view returns (PoolAddresses memory poolAddresses) {
//         poolAddresses.token0 = IUniswapV3Pool(_pool).token0();
//         poolAddresses.token1 = IUniswapV3Pool(_pool).token1();
//     }

//     function _createPosition(address _pool, uint160 _rangeNumerator) internal {
//         PoolAddresses memory addresses = getPoolAddresses(_pool);
//         uint256 token0Balance = addresses.balance0(address(this));
//         uint256 token1Balance = addresses.balance1(address(this));

//         if (token0Balance == 0) {
//             return
//                 addPositionToken1(
//                     _pool,
//                     addresses,
//                     token1Balance,
//                     _rangeNumerator
//                 );
//         }
//         if (token1Balance == 0) {
//             return
//                 addPositionToken0(
//                     _pool,
//                     addresses,
//                     token0Balance,
//                     _rangeNumerator
//                 );
//         } else {
//             revert("Not supported now");
//         }
//     }

//     function _floorTick(
//         int24 _targetTick,
//         int24 _tickSpacing
//     ) internal pure returns (int24) {
//         int24 remainder = _targetTick % _tickSpacing;
//         if (remainder == 0) return _targetTick;

//         if (_targetTick > 0) return _targetTick - remainder;

//         // solidity handling remainder of negative number is sign * (abs(num) % v)
//         return _targetTick - remainder - _tickSpacing;
//     }

//     function _ceilTick(
//         int24 _targetTick,
//         int24 _tickSpacing
//     ) internal pure returns (int24) {
//         int24 remainder = _targetTick % _tickSpacing;
//         if (remainder == 0) return _targetTick;

//         // if (_targetTick > 0) return
//         // solidity handling remainder of negative number is sign * (abs(num) % v)
//         return _targetTick - remainder;
//     }

//     /// @dev This means the lower and upper ticks are below the current tick. Caller should make sure
//     ///      targetLowerTick is smaller than curTick
//     function _skewedLowerRange(
//         int24 targetLowerTick,
//         int24 curTick,
//         int24 tickSpacing
//     ) internal pure returns (int24 lower, int24 upper) {
//         // we shift lower tick further away from current tick to be more conservative in the tick range
//         lower = _floorTick(targetLowerTick, tickSpacing);
//         upper = _floorTick(curTick - 1, tickSpacing);
//     }

//     /// @dev This means the lower and upper ticks are above the current tick. Caller should make sure
//     ///      targetUpperTick is smaller than curTick
//     function _skewedUpperRange(
//         int24 targetUpperTick,
//         int24 curTick,
//         int24 tickSpacing
//     ) internal pure returns (int24 lower, int24 upper) {
//         // we shift upper tick further away from current tick to be more conservative in the tick range
//         upper = _ceilTick(targetUpperTick, tickSpacing);
//         lower = _ceilTick(curTick + 1, tickSpacing);
//     }

//     function addPositionToken1(
//         address _pool,
//         PoolAddresses memory _addresses,
//         uint256 amount1,
//         uint160 _rangeNumerator
//     ) internal {
//         (uint160 priceSqrt, int24 currentTick) = _slot0(_pool);

//         uint160 priceSqrtLower = ((RANGE_DENOMINATOR - _rangeNumerator) *
//             priceSqrt) / RANGE_DENOMINATOR;
//         (int24 tickLower, int24 tickUpper) = _skewedLowerRange(
//             TickMath.getTickAtSqrtRatio(priceSqrtLower),
//             currentTick,
//             IUniswapV3Pool(_pool).tickSpacing()
//         );

//         LiquidityChangeOutput memory output = _addLiquidity(
//             _pool,
//             _addresses,
//             tickLower,
//             priceSqrt,
//             tickUpper,
//             0,
//             amount1
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

//     function addPositionToken0(
//         address _pool,
//         PoolAddresses memory _addresses,
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

//     /**
//      *  Used to control authorization of upgrade methods
//      */
//     function _authorizeUpgrade(
//         address newImplementation
//     ) internal view override onlyOwner {
//         newImplementation; // silence the warning
//     }
// }
