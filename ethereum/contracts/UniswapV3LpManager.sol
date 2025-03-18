// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PositionTracker, LibPositionTracker} from "./libraries/LibPositionTracker.sol";

import {LiquiditySwapV3} from "./UniswapV3LiquiditySwap.sol";
import {IUniswapV3TokenPairs, TokenPair, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";
import {LibPercentageMath} from "./RateMath.sol";
import {MintParams, LiquidityChangeOutput} from "./interfaces/IUniswapV3PoolProxy.sol";
import {ILiquiditySwapV3, SearchRange, PreSwapParam} from "./interfaces/ILiquiditySwap.sol";
import {UniswapV3PoolsProxy} from "./UniswapV3PoolsProxy.sol";

struct RebalanceParams {
    uint8 tokenPairId;
    uint160 sqrtPriceLimitX96;
    uint16 maxMintSlippageRate;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0;
    uint256 amount1;
    uint160 R_Q96;
    SearchRange searchRange;
}

struct LpPosition {
    uint8 tokenPairId;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 amount0;
    uint256 amount1;
    uint160 fee0;
    uint160 fee1;
}

/// @notice The list of parameters for uniswap V3 liquidity operations
struct OperationParams {
    /// @notice The protocol fee rate, base 1000 (e.g., 50 means 5%)
    uint16 protocolFeeRate;
}

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
contract UniswapV3LpManager is Ownable, UniswapV3PoolsProxy {
    using SafeERC20 for IERC20;
    using LibTokenId for uint8;
    using LibPositionTracker for PositionTracker;

    error NotLiquidityOwner(address sender);
    error NotBalancer(address sender);
    error InvalidAddress();
    error RateTooHigh(uint16 rate);
    error TokenPairIdNotSupported(uint8 tokenPairId);
    enum PositionChange {
        Create,
        Increase,
        Descrese,
        Closed
    }
    event PositionChanged(
        uint8 tokenPair,
        bytes32 positionKey,
        PositionChange change,
        uint256 amount0,
        uint256 amount1,
        address operator
    );
    event FeesCollected(bytes32 positionKey, uint256 fee0, uint256 fee1);
    event RemainingFundsWithdrawn(address user, uint256 amount0, uint256 amount1);

    /// @dev A util contract that checks the list of supported uniswap v3 token pairs
    IUniswapV3TokenPairs public immutable supportedTokenPairs;

    // @dev The list of configuration parameters for liquidity operations
    OperationParams public operationalParams;

    /// @notice The owner of liquidity. This address has the permission to close positions
    address public liquidityOwner;
    /// @notice The address that can rebalance the liquidity positions
    address public balancer;
    /// @notice Handles the swap of tokens during rebalancing
    ILiquiditySwapV3 public liquiditySwap;
    /// @notice Tracks each position of the LP
    PositionTracker private positionTracker;

    constructor(
        address _supportedTokenPairs,
        address _liquidityOwner,
        address _balancer
    ) {
        supportedTokenPairs = IUniswapV3TokenPairs(_supportedTokenPairs);
        liquidityOwner = _liquidityOwner;
        balancer = _balancer;

        // current contract is the owner of liquidity swap
        liquiditySwap = ILiquiditySwapV3(address(new LiquiditySwapV3()));

        operationalParams.protocolFeeRate = 50;
    }

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

    function setBalancer(address _newBalancer) public onlyOwner {
        if (_newBalancer == address(0)) {
            revert InvalidAddress();
        }
        balancer = _newBalancer;
    }

    function setProtocolFeeRate(uint16 _newRate) external onlyOwner {
        if (_newRate > 1000) {
            revert RateTooHigh(_newRate);
        }
        operationalParams.protocolFeeRate = _newRate;
    }

    function listPositionKeys(uint256 _start, uint256 _end) external view returns (uint256 total, bytes32[] memory keys) {
        total = positionTracker.length();
        keys = positionTracker.list(_start, _end);
    }

    function mint(
        uint8 _tokenPairId,
        MintParams calldata _params
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidTokenPair(_tokenPairId);

        _transferFundsAndApprove(tokenPair.token0, _params.amount0Desired);
        _transferFundsAndApprove(tokenPair.token1, _params.amount1Desired);

        bytes32 positionKey = positionTracker.tryInsertNewPositionKey(
            tokenPair.id,
            _params.tickLower,
            _params.tickUpper
        );

        LiquidityChangeOutput memory output = _mint(tokenPair, _params);

        _refund(tokenPair.token0, _params.amount0Desired, output.amount0);
        _refund(tokenPair.token1, _params.amount1Desired, output.amount1);

        positionTracker.setPositionKeyData(
            positionKey,
            _tokenPairId,
            _params.tickLower,
            _params.tickUpper
        );

        emit PositionChanged(
            _tokenPairId,
            positionKey,
            PositionChange.Create,
            output.amount0,
            output.amount1,
            msg.sender
        );
    }

    function increaseLiquidity(
        bytes32 _positionKey,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidPosition(
            _positionKey
        );

        _transferFundsAndApprove(tokenPair.token0, _amount0Desired);
        _transferFundsAndApprove(tokenPair.token1, _amount1Desired);

        (int24 tickLower, int24 tickUpper) = positionTracker.getPositionTicks(
            _positionKey
        );

        LiquidityChangeOutput memory output = _increaseLiquidity(
            tokenPair,
            tickLower,
            tickUpper,
            _amount0Desired,
            _amount1Desired,
            _amount0Min,
            _amount1Min
        );

        _refund(tokenPair.token0, _amount0Desired, output.amount0);
        _refund(tokenPair.token1, _amount1Desired, output.amount1);

        emit PositionChanged(
            tokenPair.id,
            _positionKey,
            PositionChange.Increase,
            output.amount0,
            output.amount1,
            msg.sender
        );
    }

    function decreaseLiquidity(
        bytes32 _positionKey,
        uint128 _newLiquidity,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidPosition(
            _positionKey
        );
        LiquidityChangeOutput memory output = _decreaseLiquidity(
            tokenPair,
            _positionKey,
            _newLiquidity,
            _amount0Min,
            _amount1Min
        );
        IERC20(tokenPair.token0).safeTransfer(msg.sender, output.amount0);
        IERC20(tokenPair.token1).safeTransfer(msg.sender, output.amount1);

        emit PositionChanged(tokenPair.id, _positionKey, PositionChange.Descrese, output.amount0, output.amount1, msg.sender);
    }

    /// @notice Collects all the fees associated with provided liquidity
    function batchCollectFees(
        bytes32[] calldata _positionKeys
    ) external onlyLiquidityOwner {
        uint256 length = _positionKeys.length;
        for (uint256 i = 0; i < length; ) {
            TokenPair memory tokenPair = _ensureValidPosition(
                _positionKeys[i]
            );
            _collectAllFees(tokenPair, _positionKeys[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    function collectAllFees(bytes32 _positionKey) public onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidPosition(
            _positionKey
        );
        (uint256 fee0, uint256 fee1) = _collectAllFees(tokenPair, _positionKey);
        IERC20(tokenPair.token0).safeTransfer(msg.sender, fee0);
        IERC20(tokenPair.token1).safeTransfer(msg.sender, fee1);
    }

    function rebalance1For0(
        RebalanceParams calldata _params
    ) external onlyBalancer {
        TokenPair memory tokenPair = _ensureValidTokenPair(_params.tokenPairId);

        bytes memory preSwapBytes = _preSwapBytes(_params, tokenPair, false);

        IERC20(tokenPair.token1).approve(address(liquiditySwap), _params.amount1);

        (int256 amount0Delta, int256 amount1Delta) = liquiditySwap
            .swapWithSearch1For0(
                tokenPair.pool,
                _params.sqrtPriceLimitX96,
                _params.searchRange,
                preSwapBytes
            );

        require(amount0Delta > 0 && amount1Delta < 0, "bug1");

        (bool exists, bytes32 positionKey) = positionTracker.exists(
            tokenPair.id,
            _params.tickLower,
            _params.tickUpper
        );

        LiquidityChangeOutput memory output;
        if (exists) {
            output = _rebalanceIncreaseLiquidity(
                _params,
                tokenPair,
                _params.amount0 + uint256(amount0Delta),
                _params.amount1 - uint256(-amount1Delta)
            );
            emit PositionChanged(tokenPair.id, positionKey, PositionChange.Increase, output.amount0, output.amount1, msg.sender);
        } else {
            MintParams memory params = MintParams({
                tickLower: _params.tickLower,
                tickUpper: _params.tickUpper,
                amount0Desired: _params.amount0 + uint256(amount0Delta),
                amount1Desired: _params.amount1 - uint256(-amount1Delta),
                amount0Min: LibPercentageMath.deductRate(
                    _params.amount0 + uint256(amount0Delta),
                    _params.maxMintSlippageRate
                ),
                amount1Min: LibPercentageMath.deductRate(
                    _params.amount1 - uint256(-amount1Delta),
                    _params.maxMintSlippageRate
                )
            });
            output = _mint(tokenPair, params);

            positionKey = positionTracker.tryInsertNewPositionKey(
                tokenPair.id,
                _params.tickLower,
                _params.tickUpper
            );

            emit PositionChanged(tokenPair.id, positionKey, PositionChange.Create, output.amount0, output.amount1, msg.sender);
        }
    }

    function rebalance0For1(
        RebalanceParams calldata _params
    ) external onlyBalancer {
        TokenPair memory tokenPair = _ensureValidTokenPair(_params.tokenPairId);

        bytes memory preSwapBytes = _preSwapBytes(_params, tokenPair, true);

        IERC20(tokenPair.token0).approve(address(liquiditySwap), _params.amount0);

        (int256 amount0Delta, int256 amount1Delta) = liquiditySwap
            .swapWithSearch0For1(
                tokenPair.pool,
                _params.sqrtPriceLimitX96,
                _params.searchRange,
                preSwapBytes
            );

        require(amount0Delta < 0 && amount1Delta > 0, "bug2");

        (bool exists, bytes32 positionKey) = positionTracker.exists(
            tokenPair.id,
            _params.tickLower,
            _params.tickUpper
        );

        LiquidityChangeOutput memory output;
        if (exists) {
            output = _rebalanceIncreaseLiquidity(
                _params,
                tokenPair,
                _params.amount0 - uint256(-amount0Delta),
                _params.amount1 + uint256(amount1Delta)
            );
            emit PositionChanged(tokenPair.id, positionKey, PositionChange.Increase, output.amount0, output.amount1, msg.sender);
        } else {
            MintParams memory params = MintParams({
                tickLower: _params.tickLower,
                tickUpper: _params.tickUpper,
                amount0Desired: _params.amount0 - uint256(-amount0Delta),
                amount1Desired: _params.amount1 + uint256(amount1Delta),
                amount0Min: LibPercentageMath.deductRate(
                    _params.amount0 - uint256(-amount0Delta),
                    _params.maxMintSlippageRate
                ),
                amount1Min: LibPercentageMath.deductRate(
                    _params.amount1 + uint256(amount1Delta),
                    _params.maxMintSlippageRate
                )
            });
            output = _mint(tokenPair, params);

            positionKey = positionTracker.tryInsertNewPositionKey(
                tokenPair.id,
                _params.tickLower,
                _params.tickUpper
            );

            emit PositionChanged(tokenPair.id, positionKey, PositionChange.Create, output.amount0, output.amount1, msg.sender);
        }
    }

    function rebalanceClosePosition(
        bytes32 _positionKey,
        uint256 _amount0Min,
        uint256 _amount1Min,
        bool _compoundFee
    ) external onlyBalancer {
        TokenPair memory tokenPair = _ensureValidPosition(_positionKey);
        (uint256 fee0, uint256 fee1, ) = _closePosition(tokenPair, _positionKey, _amount0Min, _amount1Min);

        if (!_compoundFee) {
            IERC20(tokenPair.token0).safeTransfer(liquidityOwner, fee0);
            IERC20(tokenPair.token1).safeTransfer(liquidityOwner, fee1);
        }

        // token stays in the contract
    }

    function closePosition(
        bytes32 _positionKey,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidPosition(_positionKey);

        (uint256 fee0, uint256 fee1, LiquidityChangeOutput memory change) = _closePosition(tokenPair, _positionKey, _amount0Min, _amount1Min);

        IERC20(tokenPair.token0).safeTransfer(msg.sender, fee0 + change.amount0);
        IERC20(tokenPair.token1).safeTransfer(msg.sender, fee1 + change.amount1);
    }

    function withdraw(uint8 _tokenPairId) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidTokenPair(_tokenPairId);

        uint256 amount0 = IERC20(tokenPair.token0).balanceOf(address(this));
        IERC20(tokenPair.token0).safeTransfer(liquidityOwner, amount0);

        uint256 amount1 = IERC20(tokenPair.token1).balanceOf(address(this));
        IERC20(tokenPair.token1).safeTransfer(liquidityOwner, amount1);

        emit RemainingFundsWithdrawn(liquidityOwner, amount0, amount1);
    }

    function position(
        bytes32 _positionKey
    ) public view returns (LpPosition memory pos) {
        TokenPair memory tokenPair = _ensureValidPosition(
            _positionKey
        );

        (pos.tokenPairId, pos.tickLower, pos.tickUpper) = positionTracker.getPositionInfo(
            _positionKey
        );

        (pos.liquidity, pos.amount0, pos.amount1, pos.fee0, pos.fee1) = _position(IUniswapV3Pool(tokenPair.pool), pos.tickLower, pos.tickUpper);
    }

    function _closePosition(
        TokenPair memory tokenPair,
        bytes32 _positionKey,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns(uint256 fee0, uint256 fee1, LiquidityChangeOutput memory output) {
        (fee0, fee1) = _collectAllFees(tokenPair, _positionKey);

        (, int24 tickLower, int24 tickUpper) = positionTracker.getPositionInfo(_positionKey);

        uint128 liquidity= _positionLiquidity(IUniswapV3Pool(tokenPair.pool), tickLower, tickUpper);

        // liquidity is now in the contract
        output = _decreaseLiquidity(
            tokenPair,
            _positionKey,
            liquidity,
            _amount0Min,
            _amount1Min
        );

        positionTracker.remove(_positionKey);

        emit PositionChanged(tokenPair.id, _positionKey, PositionChange.Closed, output.amount0, output.amount1, msg.sender);
    }

    function _decreaseLiquidity(
        TokenPair memory tokenPair,
        bytes32 _positionKey,
        uint128 _reduction,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) internal returns (LiquidityChangeOutput memory output) {
        (int24 tickLower, int24 tickUpper) = positionTracker.getPositionTicks(
            _positionKey
        );

        return
            _decreaseLiquidity(
                IUniswapV3Pool(tokenPair.pool),
                _reduction,
                tickLower,
                tickUpper,
                _amount0Min,
                _amount1Min
            );
    }

    function _collectAllFees(
        TokenPair memory tokenPair,
        bytes32 _positionKey
    ) internal returns (uint256 amount0, uint256 amount1) {
        (int24 tickLower, int24 tickUpper) = positionTracker.getPositionTicks(
            _positionKey
        );

        _decreaseLiquidity(
            IUniswapV3Pool(tokenPair.pool),
            0,
            tickLower,
            tickUpper,
            0,
            0
        );

        (amount0, amount1) = _collect(
            IUniswapV3Pool(tokenPair.pool),
            tickLower,
            tickUpper
        );

        uint256 protocolFee0 = _calculateProtocolFee(amount0);
        uint256 protocolFee1 = _calculateProtocolFee(amount1);

        IERC20(tokenPair.token0).safeTransfer(owner(), protocolFee0);
        IERC20(tokenPair.token1).safeTransfer(owner(), protocolFee1);

        amount0 -= protocolFee0;
        amount1 -= protocolFee1;

        emit FeesCollected(_positionKey, amount0, amount1);
    }

    function _calculateProtocolFee(
        uint256 amount
    ) internal view returns (uint256) {
        return (amount * operationalParams.protocolFeeRate) / 1000;
    }

    /// @notice Refund the extract amount not provided to the LP pool back to liquidity owner
    function _refund(
        address _token,
        uint256 _amountExpected,
        uint256 _amountActual
    ) internal {
        if (_amountExpected > _amountActual) {
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
    
    function _preSwapBytes(
        RebalanceParams calldata _params,
        TokenPair memory _tokenPair,
        bool zeroForOne
    ) internal returns (bytes memory) {
        int24 tickCur;
        {
            (, tickCur, , , , , ) = IUniswapV3Pool(_tokenPair.pool).slot0();
        }


        PreSwapParam memory swapData;
        
        if (zeroForOne) {
            swapData = PreSwapParam({
                amount0: _params.amount0,
                amount1: _params.amount1,
                R_Q96: _params.R_Q96,
                tokenIn: _tokenPair.token0
            });
        } else {
            swapData = PreSwapParam({
                amount0: _params.amount0,
                amount1: _params.amount1,
                R_Q96: _params.R_Q96,
                tokenIn: _tokenPair.token1
            });
        }

        return liquiditySwap.encodePreSwapData(zeroForOne, swapData);
    }

    function _rebalanceIncreaseLiquidity(
        RebalanceParams calldata _params,
        TokenPair memory _tokenPair,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (LiquidityChangeOutput memory output) {
        output = _increaseLiquidity(
            _tokenPair,
            _params.tickLower,
            _params.tickUpper,
            _amount0,
            _amount1,
            LibPercentageMath.deductRate(_amount0, _params.maxMintSlippageRate),
            LibPercentageMath.deductRate(_amount0, _params.maxMintSlippageRate)
        );
    }
}
