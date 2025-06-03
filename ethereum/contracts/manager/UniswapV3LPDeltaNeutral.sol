// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;


import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UniswapV3LpManagerAdmin} from "./UniswapV3LpManagerAdmin.sol";
import {LiquidityChangeOutput} from "../interfaces/IUniswapV3PoolProxy.sol";
import {UniswapV3PoolsUtilV2, PoolAddresses, Position} from "../UniswapV3PoolsUtilV2.sol";

library LibPoolAddresses {
    function balance0(PoolAddresses memory self, address _who) internal view returns (uint256) {
        return IERC20(self.token0).balanceOf(_who);
    }

    function balance1(PoolAddresses memory self, address _who) internal view returns (uint256) {
        return IERC20(self.token1).balanceOf(_who);
    }
}

/// @dev The delta neutral state of a position
struct DeltaNeutralState {
    /// @dev The target volatile token exposure of the position, i.e. maintain this amount of volatile token
    uint256 targetExposure;
    /// @dev A flag indicates if token 0 is the target token to achieve delta neutral
    bool isToken0Target;
    /// @dev The balance of base token that will be swapped to target token to achieve delta neutral
    uint256 deltaBaseBalance;
    /// @dev The amount of target token obtained from swapping base token
    uint256 deltaTargetBalance;
}

contract UniswapV3LPDeltaNeutral is
    UUPSUpgradeable,
    UniswapV3PoolsUtilV2,
    UniswapV3LpManagerAdmin
{
    using SafeERC20 for IERC20;
    using LibPoolAddresses for PoolAddresses;

    uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;
    uint160 constant RANGE_DENOMINATOR = 100000;

    mapping(address => DeltaNeutralState) public states;
    mapping(address => Position) public positions;

    event PositionOpen(address pool, int24 tickLower, uint160 priceSqrt, int24 tickUpper, uint256 amount0, uint256 amount1);
    event PostionClosed(address pool, int24 tickLower, int24 tickUpper, uint128 amount0, uint128 amount1);

    error StillInRange();
    error PoolHasActivePosition();
    error DeltaNeutralNoConfig();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _liquidityOwner,
        address _balancer
    ) external initializer {
        __Ownable_init();

        liquidityOwner = _liquidityOwner;
        balancer = _balancer;
    }

    function isDeltaNeutralConfiged(address _pool) public view returns (bool) {
        return states[_pool].targetExposure > 0;
    }

    function hasPositionInPool(address _pool) public view returns (bool) {
        return positions[_pool].liquidity > 0;
    }

    function getPoolPositionInfo(address _pool) external view returns(Position memory pos, bool inRange) {
        pos = positions[_pool];
        inRange = isPositionInRange(_pool, pos);
    }

    /// @dev Try to neutralize the volatile token delta.
    /// @param _deltaTolerance The volatile token tolerance. If the current position's delta is within this number, txn reverts.
    function neutralizeVolatileExposure(address _pool, uint256 _deltaTolerance) external onlyAddress(balancer) {

    }

    /// @dev Create the delta neutral params for a pool
    /// @param _isToken0Target A flag indicates if token 0 is the target token to achieve delta neutral
    /// @param _targetExposure The target token amount that the lp position should maintain
    /// @param _baseTokenBudget The balance of base token that will be swapped to target token to achieve delta neutral
    function configDeltaNeutral(
        address _pool,
        bool _isToken0Target,
        uint256 _targetExposure,
        uint256 _baseTokenBudget
    ) external onlyAddress(balancer) {
        if (hasPositionInPool(_pool)) {
            revert PoolHasActivePosition();
        }

        states[_pool].isToken0Target = _isToken0Target;

        if (_isToken0Target) {
            // this means token 0 is the target token to achieve 0 delta, we will use token 1 to swap
            _transferIn(_pool, _targetExposure, _baseTokenBudget);

        } else {
            // this means token 1 is the target token to achieve 0 delta, we will use token 0 to swap
            _transferIn(_pool, _baseTokenBudget, _targetExposure);
        }

        states[_pool].deltaBaseBalance = _baseTokenBudget;
        states[_pool].targetExposure = _targetExposure;
    }

    function rebalance(address _pool, uint160 _rangeNumerator) external onlyAddress(balancer) {
        if (!isDeltaNeutralConfiged(_pool)) revert DeltaNeutralNoConfig();

        Position memory position = positions[_pool];
        if (position.liquidity == 0) {
            _createPosition(_pool, _rangeNumerator);
        } else {
            _processCurrentPosition(_pool, position, _rangeNumerator);
        }
    }

    function closePosition(address _pool, Position memory _position) public onlyAddress(balancer) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        _collectFees(pool, _position);
        _burnAll(pool, _position);
        (uint128 amount0Collected, uint128 amount1Collected) = _collect(
            pool,
            address(this),
            _position,
            UINT128_MAX,
            UINT128_MAX
        );

        delete positions[_pool];

        emit PostionClosed(_pool, _position.tickLower, _position.tickUpper, amount0Collected, amount1Collected);
    }

    function withdraw(address _token) external onlyOwner() {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(liquidityOwner, balance);
    }

    function withdraw(address _token, uint256 _amount) external onlyOwner() {
        IERC20(_token).transfer(liquidityOwner, _amount);
    }

    // ==================== Internal Methods ====================

    function _transferIn(address _pool, uint256 _amount0, uint256 _amount1) internal {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        if (_amount0 > 0) {
            address token0 = pool.token0();
            IERC20(token0).safeTransferFrom(msg.sender, address(this), _amount0);
        }

        if (_amount1 > 0) {
            address token1 = pool.token1();
            IERC20(token1).safeTransferFrom(msg.sender, address(this), _amount1);
        }
    }

    function isPositionInRange(address _pool, Position memory _position) internal view returns (bool) {
        (, int24 currentTick) = _slot0(_pool);
        return _position.tickLower <= currentTick && currentTick <= _position.tickUpper;
    }

    function _processCurrentPosition(address _pool, Position memory _position, uint160 _rangeNumerator) internal {
        (, int24 currentTick) = _slot0(_pool);
        if (_position.tickLower <= currentTick && currentTick <= _position.tickUpper) {
            revert StillInRange();
        }

        closePosition(_pool, _position);
        _createPosition(_pool, _rangeNumerator);
    }

    function _getPoolAddresses(address _pool) internal view returns (PoolAddresses memory poolAddresses) {
        poolAddresses.token0 = IUniswapV3Pool(_pool).token0();
        poolAddresses.token1 = IUniswapV3Pool(_pool).token1();
    }

    function _createPosition(address _pool, uint160 _rangeNumerator) internal {
        PoolAddresses memory addresses = _getPoolAddresses(_pool);

        if (states[_pool].isToken0Target) _addPositionToken0(_pool, addresses, states[_pool].targetExposure, _rangeNumerator);
        else _addPositionToken1(_pool, addresses, states[_pool].targetExposure, _rangeNumerator);
    }

    // function floorTick(int24 targetTick, int24 tickSpacing) public pure returns (int24) {
    //     int24 remainder = targetTick % tickSpacing;
        
    //     int24 tick = targetTick - remainder;

    //     if (targetTick < 0 && remainder != 0) {
    //         tick -= tickSpacing;
    //     }

    //     return tick;
    // }

    // function ceilTick(int24 targetTick, int24 tickSpacing) public pure returns (int24) {
    //     int24 remainder = targetTick % tickSpacing;
    //     if (remainder == 0) {
    //         return targetTick; // already aligned
    //     }

    //     int24 tick = targetTick - remainder;

    //     if (targetTick > 0) {
    //         tick += tickSpacing;
    //     }
    //     return tick;
    // }

    function _addPositionToken1(address _pool, PoolAddresses memory _addresses, uint256 amount1, uint160 _rangeNumerator) internal {
        (uint160 priceSqrt, int24 currentTick) = _slot0(_pool);

        uint160 priceSqrtLower = (RANGE_DENOMINATOR - _rangeNumerator) * priceSqrt / RANGE_DENOMINATOR;
        int24 tickLower = TickMath.getTickAtSqrtRatio(priceSqrtLower);
        int24 tickUpper = currentTick - 1;

        LiquidityChangeOutput memory output = _addLiquidity(
            _pool,
            _addresses,
            tickLower,
            priceSqrt,
            tickUpper,
            0,
            amount1
        );

        positions[_pool].tickLower = tickLower;
        positions[_pool].tickUpper = tickUpper;
        positions[_pool].liquidity = output.liquidity;

        emit PositionOpen(_pool, tickLower, priceSqrt, tickUpper, output.amount0, output.amount1);
    }

    function _addPositionToken0(address _pool, PoolAddresses memory _addresses, uint256 amount0, uint160 _rangeNumerator) internal {
        (uint160 priceSqrt, int24 currentTick) = _slot0(_pool);

        uint160 priceSqrtLower = (RANGE_DENOMINATOR + _rangeNumerator) * priceSqrt / RANGE_DENOMINATOR;
        int24 tickUpper = TickMath.getTickAtSqrtRatio(priceSqrtLower);
        int24 tickLower = currentTick + 1;

        LiquidityChangeOutput memory output = _addLiquidity(
            _pool,
            _addresses,
            tickLower,
            priceSqrt,
            tickUpper,
            amount0,
            0
        );

        positions[_pool].tickLower = tickLower;
        positions[_pool].tickUpper = tickUpper;
        positions[_pool].liquidity = output.liquidity;

        emit PositionOpen(_pool, tickLower, priceSqrt, tickUpper, output.amount0, output.amount1);
    }

    /**
     *  Used to control authorization of upgrade methods
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        newImplementation; // silence the warning
    }

    function _collectFees(
        IUniswapV3Pool _pool,
        Position memory _position
    ) internal {
        _pool.burn(_position.tickLower, _position.tickUpper, 0);
        (uint128 fee0, uint128 fee1) = _tokensOwned(_pool, _position);
        _collect(_pool, liquidityOwner, _position, fee0, fee1);
    }
}
