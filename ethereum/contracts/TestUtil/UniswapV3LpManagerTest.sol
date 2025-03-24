// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PositionTracker, LibPositionTracker} from "../libraries/LibPositionTracker.sol";
import {FeeEarnedTracker, LibFeeEarnedTracker} from "../libraries/LibFees.sol";

import {LiquiditySwapV3} from "../UniswapV3LiquiditySwap.sol";
import {IUniswapV3TokenPairs, TokenPair, LibTokenId} from "../interfaces/IUniswapV3TokenPairs.sol";
import {LiquidityChangeOutput} from "../interfaces/IUniswapV3PoolProxy.sol";
import {UniswapV3PoolsProxy} from "../UniswapV3PoolsProxy.sol";

struct MintParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
}

/// @notice The list of parameters for uniswap V3 liquidity operations
struct OperationParams {
    /// @notice The protocol fee rate, base 1000 (e.g., 50 means 5%)
    uint16 protocolFeeRate;
}

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
contract UniswapV3LpManagerTest is Ownable, UniswapV3PoolsProxy {
    uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;

    using SafeERC20 for IERC20;
    using LibTokenId for uint8;
    using LibPositionTracker for PositionTracker;
    using LibFeeEarnedTracker for FeeEarnedTracker;

    error NotActivated();
    error NotDeactivated();
    error NotLiquidityOwner(address sender);
    error NotBalancer(address sender);
    error InvalidAddress();
    error TooMuchLiquidityToWithdraw(uint256 num);
    error RateTooHigh(uint16 rate);
    error TokenPairIdNotSupported(uint8 tokenPairId);

    enum PositionChange {
        Create,
        Increase,
        Descrese,
        Closed
    }
    event PositionChanged(
        bytes32 positionKey,
        PositionChange change,
        uint256 amount0,
        uint256 amount1,
        address operator
    );
    event FeesCollected(
        bytes32 positionKey,
        uint128 fee0,
        uint128 fee1,
        uint128 protocolFee0,
        uint128 protocolFee1
    );
    event RemainingFundsWithdrawn(
        address user,
        uint256 amount0,
        uint256 amount1
    );

    /// @dev A util contract that checks the list of supported uniswap v3 token pairs
    IUniswapV3TokenPairs public immutable supportedTokenPairs;

    // @dev The list of configuration parameters for liquidity operations
    OperationParams public operationalParams;

    /// @notice The owner of liquidity. This address has the permission to close positions
    address public liquidityOwner;
    /// @notice The address that can rebalance the liquidity positions
    address public balancer;
    /// @notice Tracks each position of the LP
    PositionTracker private positionTracker;
    FeeEarnedTracker private feeEarnedTracker;

    /// @notice The position manager is deavtivated
    bool public deactivated;

    constructor(
        address _supportedTokenPairs,
        address _liquidityOwner,
        address _balancer
    ) {
        supportedTokenPairs = IUniswapV3TokenPairs(_supportedTokenPairs);
        liquidityOwner = _liquidityOwner;
        balancer = _balancer;

        operationalParams.protocolFeeRate = 50;
        deactivated = false;
    }

    modifier onlyActivated() {
        if (deactivated) {
            revert NotLiquidityOwner(msg.sender);
        }
        _;
    }

    modifier onlyDeactivated() {
        if (!deactivated) {
            revert NotLiquidityOwner(msg.sender);
        }
        _;
    }

    modifier onlyLiquidityOwner() {
        if (msg.sender != liquidityOwner) {
            revert NotLiquidityOwner(msg.sender);
        }
        _;
    }

    function mint(
        uint8 _tokenPairId,
        MintParams calldata _params
    ) external onlyLiquidityOwner onlyActivated {
        TokenPair memory tokenPair = _ensureValidTokenPair(_tokenPairId);

        _transferIn(tokenPair, _params.amount0Desired, _params.amount1Desired);

        bytes32 positionKey = positionTracker.tryInsertNewPosition(
            tokenPair.id,
            _params.tickLower,
            _params.tickUpper
        );

        LiquidityChangeOutput memory output = _addLiquidity(
            tokenPair,
            _params.tickLower,
            _params.tickUpper,
            _params.amount0Desired,
            _params.amount1Desired,
            _params.amount0Min,
            _params.amount1Min
        );

        _refund(
            msg.sender,
            tokenPair.token0,
            _params.amount0Desired,
            output.amount0
        );
        _refund(
            msg.sender,
            tokenPair.token1,
            _params.amount1Desired,
            output.amount1
        );

        emit PositionChanged(
            positionKey,
            PositionChange.Create,
            output.amount0,
            output.amount1,
            msg.sender
        );
    }

    function _add(uint256 _num, int256 _val) internal pure returns (uint256) {
        if (_val >= 0) {
            return _num + uint256(_val);
        }
        return _num - uint256(-_val);
    }

    /// @notice Refund the extract amount not provided to the LP pool back to liquidity owner
    function _refund(
        address _recipient,
        address _token,
        uint256 _amountExpected,
        uint256 _amountActual
    ) internal {
        if (_amountExpected > _amountActual) {
            IERC20(_token).safeTransfer(
                _recipient,
                _amountExpected - _amountActual
            );
        }
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferIn(
        TokenPair memory _tokenPair,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        IERC20(_tokenPair.token0).safeTransferFrom(
            msg.sender,
            address(this),
            _amount0
        );
        IERC20(_tokenPair.token1).safeTransferFrom(
            msg.sender,
            address(this),
            _amount1
        );
    }

    function _ensureValidTokenPair(
        uint8 _id
    ) internal view returns (TokenPair memory tokenPair) {
        tokenPair = supportedTokenPairs.getTokenPair(_id);

        if (!LibTokenId.isValidTokenPairId(tokenPair.id)) {
            revert TokenPairIdNotSupported(_id);
        }
    }

    function _ensureValidPosition(
        bytes32 _positionKey
    ) internal view returns (TokenPair memory tokenPair) {
        uint8 tokenPairId = positionTracker.getPositionTokenPair(_positionKey);
        tokenPair = _ensureValidTokenPair(tokenPairId);
    }
}
