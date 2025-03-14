// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {LiquiditySwapV3} from "./UniswapV3LiquiditySwap.sol";
import {IUniswapV3TokenPairs, TokenPair, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";
import {LibPercentageMath} from "./RateMath.sol";
import {UniswapV3PositionLib, Position} from "./libraries/UniswapV3PositionLib.sol";
import "./interfaces/IUniswapV3PositionManager.sol";
import {ILiquiditySwapV3, SearchRange} from "./interfaces/ILiquiditySwap.sol";

struct RebalanceParams {
    uint256 positionId;
    uint16 sqrtPriceLimitX96;
    int24 tickLower;
    int24 tickUpper;
    SearchRange searchRange;
    bytes preSwapCalldata;
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
contract UniswapV3LpHandlerV2 {
    using SafeERC20 for IERC20;
    using LibTokenId for uint8;

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
    error TokenPairIdNotSupported(uint8 tokenPairId);

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

    /// @dev A util contract that checks the list of supported uniswap v3 token pairs
    IUniswapV3TokenPairs public immutable supportedTokenPairs;

    // @dev The list of configuration parameters for liquidity operations
    OperationParams public operationalParams;

    /// @notice The owner of liquidity. This address has the permission to close positions
    address public liquidityOwner;
    /// @notice The address that can rebalance the liquidity positions
    address public balancer;
    /// @notice The address of LP manager contract that can manage liquidity positions
    address public lpManager;
    /// @notice Handles the swap of tokens during rebalancing
    ILiquiditySwapV3 public liquiditySwap;

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
        IUniswapV3TokenPairs _supportedTokenPairs,
        address _lpManager,
        // deprecated field
        address _factory,
        address _liquidityOwner,
        address _balancer
    ) {
        supportedTokenPairs = _supportedTokenPairs;
        lpManager = _lpManager;
        liquidityOwner = _liquidityOwner;
        balancer = _balancer;

        // current contract is the owner of liquidity swap
        liquiditySwap = ILiquiditySwapV3(address(new LiquiditySwapV3()));

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
        uint8 tokenPairId,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    )
        external
        payable
        onlyLiquidityOwner
        validateTickRange(tickLower, tickUpper)
    {
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(
            tokenPairId
        );
        if (!LibTokenId.isValidTokenPairId(tokenPair.id)) {
            revert TokenPairIdNotSupported(tokenPairId);
        }

        _transferFundsAndApprove(tokenPair.token0, amount0);
        _transferFundsAndApprove(tokenPair.token1, amount1);

        (
            ,
            ,
            uint256 amount0Minted,
            uint256 amount1Minted
        ) = IUniswapV3PositionManager(lpManager).mint(
                tokenPair,
                tickLower,
                tickUpper,
                amount0,
                amount1,
                operationalParams.maxMintSlippageRate
            );

        _refund(tokenPair.token0, amount0, amount0Minted);
        _refund(tokenPair.token1, amount1, amount1Minted);
    }

    function _validateTokenPairAndPosition(
        uint256 positionId
    )
        internal
        view
        returns (TokenPair memory tokenPair, uint256 amount0, uint256 amount1)
    {
        (tokenPair, amount0, amount1) = IUniswapV3PositionManager(lpManager)
            .getPoolInfo(positionId);

        if (
            !LibTokenId.isValidTokenPairId(tokenPair.id) ||
            tokenPair.pool == address(0)
        ) {
            revert TokenPairIdNotSupported(tokenPair.id);
        }
    }

    function increaseLiquidity(
        uint256 positionId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external payable onlyLiquidityOwner {
        (TokenPair memory tokenPair, , ) = _validateTokenPairAndPosition(
            positionId
        );

        _transferFundsAndApprove(tokenPair.token0, amount0Desired);
        _transferFundsAndApprove(tokenPair.token1, amount1Desired);

        uint16 maxMintSlippageRate = operationalParams.maxMintSlippageRate;
        uint256 amount0Min = LibPercentageMath.multiply(
            amount0Desired,
            maxMintSlippageRate
        );
        uint256 amount1Min = LibPercentageMath.multiply(
            amount1Desired,
            maxMintSlippageRate
        );

        (
            ,
            uint256 amount0Minted,
            uint256 amount1Minted
        ) = IUniswapV3PositionManager(lpManager).increaseLiquidity(
                tokenPair,
                positionId,
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min
            );

        _refund(tokenPair.token0, amount0Desired, amount0Minted);
        _refund(tokenPair.token1, amount1Desired, amount1Minted);
    }

    function decreaseLiquidity(
        uint256 positionId,
        uint16 percentage,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable onlyLiquidityOwner {
        (TokenPair memory tokenPair, , ) = _validateTokenPairAndPosition(
            positionId
        );

        (uint256 amount0, uint256 amount1) = IUniswapV3PositionManager(
            lpManager
        ).decreaseLiquidity(
                tokenPair.pool,
                positionId,
                percentage,
                amount0Min,
                amount1Min
            );

        amount0 = _adjustAmountByBalance(tokenPair.token0, amount0);
        amount1 = _adjustAmountByBalance(tokenPair.token1, amount1);

        UniswapV3PositionLib.sendTokens(msg.sender, tokenPair.token0, amount0);
        UniswapV3PositionLib.sendTokens(msg.sender, tokenPair.token1, amount1);
    }

    function _adjustAmountByBalance(
        address token,
        uint256 amount
    ) internal view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        return amount;
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
        (TokenPair memory tokenPair, , ) = _validateTokenPairAndPosition(
            positionId
        );
        (uint256 amount0, uint256 amount1) = IUniswapV3PositionManager(
            lpManager
        ).collect(
                tokenPair.pool,
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
                tokenPair.token0,
                protocolFee0
            );
        }

        if (protocolFee1 != 0) {
            UniswapV3PositionLib.sendTokens(
                liquidityOwner,
                tokenPair.token1,
                protocolFee1
            );
        }

        UniswapV3PositionLib.sendTokens(
            msg.sender,
            tokenPair.token0,
            amount0 - protocolFee0
        );
        UniswapV3PositionLib.sendTokens(
            msg.sender,
            tokenPair.token1,
            amount1 - protocolFee1
        );
        emit FeesCollected(positionId, amount0, amount1);
    }

    function balance1For0(
        RebalanceParams calldata params

    ) external {

    }

    function rebalance(
        
    )
        external
        onlyBalancer
        validateTickRange(params.tickLower, params.tickUpper)
    {
        (
            TokenPair memory tokenPair,
            uint256 amount0,
            uint256 amount1
        ) = _validateTokenPairAndPosition(params.positionId);

        // 1. swap
        _trySwap(
            tokenPair,
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
        ) = IUniswapV3PositionManager(lpManager).mint(
                tokenPair,
                params.tickLower,
                params.tickUpper,
                params.newAmount0,
                params.newAmount1,
                operationalParams.maxMintSlippageRate
            );

        // update position
        IUniswapV3PositionManager(lpManager).updatePosition(
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
        uint16 percentage,
        uint256 amount0Min,
        uint256 amount1Min
    ) external onlyBalancer {
        (TokenPair memory tokenPair, , ) = _validateTokenPairAndPosition(
            positionId
        );
        // collect fee
        IUniswapV3PositionManager(lpManager).collect(
            tokenPair.pool,
            positionId,
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        IUniswapV3PositionManager(lpManager).decreaseLiquidity(
            tokenPair.pool,
            positionId,
            percentage,
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
        TokenPair memory tokenPair,
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
            tokenPair.token0,
            tokenPair.token1,
            tokenPair.poolFee,
            amountIn,
            amountOutMinimum,
            isToken0ToToken1
        );
    }

    /// @notice Refund the extract amount not provided to the LP pool back to liquidity owner
    function _refund(
        address _token,
        uint256 _amountExpected,
        uint256 _amountActual
    ) internal {
        if (_amountExpected > _amountActual) {
            IERC20(_token).forceApprove(address(lpManager), 0);
            IERC20(_token).safeTransfer(
                msg.sender,
                _amountExpected - _amountActual
            );
        }
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferFundsAndApprove(
        address _token,
        uint256 _amount
    ) internal {
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_token).forceApprove(lpManager, _amount);
    }
}
