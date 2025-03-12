// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./UniswapV3SwapPool.sol";
import {LibPercentageMath} from "./RateMath.sol";
import {UniswapV3PositionLib, Position} from "./libraries/UniswapV3PositionLib.sol";
import "./interfaces/IUniswapV3LpManager.sol";

struct RebalanceParams {
    uint256 positionId;
    uint256 amount0WithdrawMin;
    uint256 amount1WithdrawMin;
    uint16 swapSlippage;
    uint256 newAmount0;
    uint256 newAmount1;
    int24 tickLower;
    int24 tickUpper;
}

/// @notice The list of parameters for uniswap V3 liquidity operations
struct OperationParams {
    /// @notice True means the fee collected will be used into new position
    bool isCompoundFee;
    /// @notice The max slippage allowed when providing liquidity
    uint16 maxMintSlippageRate;
    /// @notice The protocol fee rate, base 1000 (e.g., 50 means 5%)
    uint16 protocolFeeRate;
}

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
contract UniswapV3LpHandlerV2 is UniswapV3SwapPool {
    using SafeERC20 for IERC20;

    error InvalidPositionId(uint256 positionId);
    error InsufficientLiquidity(uint256 positionId);
    error NotLiquidityOwner(address sender);
    error NotBalancer(address sender);
    error InvalidTickRange(int24 tickLower, int24 tickUpper);
    error NotSwapable(
        uint256 reserve0,
        uint256 reserve1,
        uint256 target0,
        uint256 target1
    );
    error InvalidAddress();
    error RateTooHigh(uint16 rate);

    /// @notice Emitted when a position is rebalanced to a new tick range
    /// @param positionId The ID of the position for which position was rebalanced
    /// @param liquidity The amount of liquidity in the rebalanced position
    /// @param amount0 The amount of token0 used to create the position
    /// @param amount1 The amount of token1 used to create the position
    /// @param tickLower The new lower tick of the position
    /// @param tickUpper The new upper tick of the position
    event PositionRebalanced(
        uint256 indexed positionId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    );
    /// @notice Emitted when fees are collected from a position
    /// @param positionId The ID of the position for which fees were collected
    /// @param fee0 The amount of token0 fees that were collected
    /// @param fee1 The amount of token1 fees that were collected
    event FeesCollected(uint256 indexed positionId, uint256 fee0, uint256 fee1);

    // @dev The list of configuration parameters for liquidity operations
    OperationParams public operationalParams;

    /// @notice The owner of liquidity. This address has the permission to close positions
    address public liquidityOwner;
    /// @notice The address that can rebalance the liquidity positions
    address public balancer;
    /// @notice The address of LP manager contract that can manage liquidity positions
    address public lpManager;

    modifier onlyLiquidityOwner() {
        if (msg.sender != liquidityOwner) {
            revert NotLiquidityOwner(msg.sender);
        }
        _;
    }

    modifier onlyBalancer() {
        if (msg.sender != balancer) {
            revert NotBalancer(msg.sender);
        }
        _;
    }

    modifier validateTickRange(int24 _tickLower, int24 _tickUpper) {
        if (_tickLower >= _tickUpper) {
            revert InvalidTickRange(_tickLower, _tickUpper);
        }
        _;
    }

    constructor(
        address _lpManager,
        address _factory,
        address _liquidityOwner,
        address _balancer
    ) UniswapV3SwapPool(_factory) {
        lpManager = _lpManager;
        liquidityOwner = _liquidityOwner;
        balancer = _balancer;

        // max slippage is 3%
        operationalParams.maxMintSlippageRate = 30;
        operationalParams.isCompoundFee = true;
        operationalParams.protocolFeeRate = 50;
    }

    function setLpManager(address _lpManager) public onlyLiquidityOwner {
        if (_lpManager == address(0)) {
            revert InvalidAddress();
        }
        lpManager = _lpManager;
    }

    function setLiquidityOwner(address _newOwner) public onlyLiquidityOwner {
        if (_newOwner == address(0)) {
            revert InvalidAddress();
        }
        liquidityOwner = _newOwner;
    }

    function setBalancer(address _newBalancer) public onlyLiquidityOwner {
        if (_newBalancer == address(0)) {
            revert InvalidAddress();
        }
        balancer = _newBalancer;
    }

    function setProtocolFeeRate(uint16 _newRate) external onlyLiquidityOwner {
        if (_newRate > 1000) {
            revert RateTooHigh(_newRate);
        }
        operationalParams.protocolFeeRate = _newRate;
    }

    function setMaxMintSlippageRate(uint16 newRate) external onlyBalancer {
        if (newRate > 1000) {
            revert RateTooHigh(newRate);
        }
        operationalParams.maxMintSlippageRate = newRate;
    }

    function setCompoundFee(bool compound) external onlyLiquidityOwner {
        operationalParams.isCompoundFee = compound;
    }

    function mint(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) external payable onlyLiquidityOwner {
        IUniswapV3LpManager(lpManager).mint(
            token0,
            token1,
            fee,
            tickLower,
            tickUpper,
            amount0,
            amount1,
            operationalParams.maxMintSlippageRate
        );
    }

    function increaseLiquidity(
        uint256 positionId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external payable onlyLiquidityOwner {
        (, PoolAddress.PoolKey memory poolKey, , ) = IUniswapV3LpManager(
            lpManager
        ).getPoolInfo(positionId);

        _transferFundsAndApprove(poolKey.token0, amount0Desired);
        _transferFundsAndApprove(poolKey.token1, amount1Desired);

        uint16 maxMintSlippageRate = operationalParams.maxMintSlippageRate;
        uint256 amount0Min = LibPercentageMath.multiply(
            amount0Desired,
            maxMintSlippageRate
        );
        uint256 amount1Min = LibPercentageMath.multiply(
            amount1Desired,
            maxMintSlippageRate
        );

        (, uint256 amount0Minted, uint256 amount1Minted) = IUniswapV3LpManager(
            lpManager
        ).increaseLiquidity(
                positionId,
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min
            );

        _refund(poolKey.token0, amount0Desired, amount0Minted);
        _refund(poolKey.token1, amount1Desired, amount1Minted);
    }

    function decreaseLiquidity(
        uint256 positionId,
        uint16 percentage,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable onlyLiquidityOwner {
        (, PoolAddress.PoolKey memory poolKey, , ) = IUniswapV3LpManager(
            lpManager
        ).getPoolInfo(positionId);
        (uint256 amount0, uint256 amount1) = IUniswapV3LpManager(lpManager)
            .decreaseLiquidity(positionId, percentage, amount0Min, amount1Min);

        UniswapV3PositionLib.sendTokens(msg.sender, poolKey.token0, amount0);
        UniswapV3PositionLib.sendTokens(msg.sender, poolKey.token1, amount1);
    }

    /// @notice Collects all the fees associated with provided liquidity
    /// @param positionIds The ids of the position to mint in uniswap v3
    function batchCollectFees(
        uint256[] calldata positionIds
    ) external onlyLiquidityOwner {
        uint256 length = positionIds.length;
        for (uint256 i = 0; i < length; ) {
            collectAllFees(positionIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @param positionId The id of the position to mint in uniswap v3
    function collectAllFees(uint256 positionId) public onlyLiquidityOwner {
        (
            uint256 amount0,
            uint256 amount1,
            PoolAddress.PoolKey memory poolKey
        ) = IUniswapV3LpManager(lpManager).collect(
                positionId,
                address(this),
                type(uint128).max,
                type(uint128).max
            );
        uint256 protocolFee0 = _calculateProtocolFee(amount0);
        uint256 protocolFee1 = _calculateProtocolFee(amount1);

        if (protocolFee0 != 0) {
            UniswapV3PositionLib.sendTokens(
                liquidityOwner,
                poolKey.token0,
                protocolFee0
            );
        }

        if (protocolFee1 != 0) {
            UniswapV3PositionLib.sendTokens(
                liquidityOwner,
                poolKey.token1,
                protocolFee1
            );
        }

        UniswapV3PositionLib.sendTokens(
            msg.sender,
            poolKey.token0,
            amount0 - protocolFee0
        );
        UniswapV3PositionLib.sendTokens(
            msg.sender,
            poolKey.token1,
            amount1 - protocolFee1
        );
        emit FeesCollected(positionId, amount0, amount1);
    }

    function rebalance(
        RebalanceParams calldata params
    )
        external
        onlyBalancer
        validateTickRange(params.tickLower, params.tickUpper)
    {
        (
            ,
            PoolAddress.PoolKey memory poolKey,
            uint256 amount0,
            uint256 amount1
        ) = IUniswapV3LpManager(lpManager).getPoolInfo(params.positionId);

        // 1. swap
        _trySwap(
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            amount0,
            amount1,
            params.newAmount0,
            params.newAmount1,
            params.swapSlippage
        );

        // 2. add new liquidity
        (
            uint256 positionId,
            uint128 liquidity,
            uint256 amount0Min,
            uint256 amount1Min
        ) = IUniswapV3LpManager(lpManager).mint(
                poolKey.token0,
                poolKey.token1,
                poolKey.fee,
                params.tickLower,
                params.tickUpper,
                params.newAmount0,
                params.newAmount1,
                operationalParams.maxMintSlippageRate
            );

        // update position
        IUniswapV3LpManager(lpManager).updatePosition(
            params.positionId,
            positionId
        );

        emit PositionRebalanced(
            positionId,
            liquidity,
            amount0Min,
            amount1Min,
            params.tickLower,
            params.tickUpper
        );
    }

    function collectFeesAndReduceLiquidity(
        uint256 positionId,
        uint256 amount0Min,
        uint256 amount1Min
    ) external onlyBalancer {
        // collect fee
        IUniswapV3LpManager(lpManager).collect(
            positionId,
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        IUniswapV3LpManager(lpManager).decreaseLiquidity(
            positionId,
            LibPercentageMath.percentage100(),
            amount0Min,
            amount1Min
        );
    }

    function _calculateProtocolFee(
        uint256 amount
    ) internal view returns (uint256) {
        return (amount * operationalParams.protocolFeeRate) / 1000;
    }

    function _trySwap(
        address token0,
        address token1,
        uint24 fee,
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _target0,
        uint256 _target1,
        uint16 _slippage
    ) internal {
        uint256 amountOutMinimum;
        uint256 amountIn;
        bool isToken0ToToken1;

        if (_reserve0 > _target0 && _reserve1 < _target1) {
            amountIn = _reserve0 - _target0;
            amountOutMinimum = UniswapV3PositionLib.calculateAmountOutMinimum(
                _target1,
                _reserve1,
                _slippage
            );
            isToken0ToToken1 = true;
        } else if (_reserve0 < _target0 && _reserve1 > _target1) {
            amountIn = _reserve1 - _target1;
            amountOutMinimum = UniswapV3PositionLib.calculateAmountOutMinimum(
                _target0,
                _reserve0,
                _slippage
            );
            isToken0ToToken1 = false;
        } else {
            revert NotSwapable(_reserve0, _reserve1, _target0, _target1);
        }

        _swap(
            token0,
            token1,
            fee,
            amountIn,
            amountOutMinimum,
            isToken0ToToken1
        );
    }

    /// @notice Refund the extract amount not provided to the LP pool back to liquidity owner
    function _refund(
        address _positionAddress,
        uint256 _amountExpected,
        uint256 _amountActual
    ) internal {
        UniswapV3PositionLib.refundExcess(
            _positionAddress,
            _amountExpected,
            _amountActual,
            msg.sender
        );
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferFundsAndApprove(
        address _positionAddress,
        uint256 _amount
    ) internal {
        UniswapV3PositionLib.transferAndApprove(
            _positionAddress,
            _amount,
            msg.sender,
            address(this)
        );
    }
}
