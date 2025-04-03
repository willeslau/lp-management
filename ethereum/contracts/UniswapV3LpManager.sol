// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {PositionTracker, LibPositionTracker} from "./libraries/LibPositionTracker.sol";
import {TokenPairAmountTracker, LibTokenPairAmountTracker} from "./libraries/LibTokenPairAmount.sol";

import {LiquiditySwapV3} from "./UniswapV3LiquiditySwap.sol";
import {IUniswapV3TokenPairs, TokenPair, LibTokenId} from "./interfaces/IUniswapV3TokenPairs.sol";
import {LibPercentageMath} from "./RateMath.sol";
import {LiquidityChangeOutput} from "./interfaces/IUniswapV3PoolProxy.sol";
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

struct RebalanceCalParams {
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
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
    uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;

    using SafeERC20 for IERC20;
    using LibTokenId for uint8;
    using LibPositionTracker for PositionTracker;
    using LibTokenPairAmountTracker for TokenPairAmountTracker;

    error NotActivated();
    error NotRebalanceable();
    error NotDeactivated();
    error NotLiquidityOwner(address sender);
    error NotBalancer(address sender);
    error InvalidAddress();
    error TooMuchLiquidityToWithdraw(uint256 num);
    error RateTooHigh(uint16 rate);
    error TokenPairIdNotSupported(uint8 tokenPairId);
    error RebalanceExceedReserve(uint256 reserve0, uint256 reserve1, uint256 requested0, uint256 requested1);

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
    event InjectedPriciple(
        uint8 tokenPair,
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
    /// @notice Handles the swap of tokens during rebalancing
    ILiquiditySwapV3 public liquiditySwap;
    /// @notice Tracks each position of the LP
    PositionTracker private positionTracker;
    /// @notice Amount of reserves for each pool, i.e. amount that can be used for next rebalance
    TokenPairAmountTracker private reserves;
    /// @notice The amount of fee earned for each pool
    TokenPairAmountTracker private feeEarned;

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

        // current contract is the owner of liquidity swap
        liquiditySwap = ILiquiditySwapV3(address(new LiquiditySwapV3()));

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

    modifier onlyBalancer() {
        if (msg.sender != balancer) {
            revert NotBalancer(msg.sender);
        }
        _;
    }

    function setDeactivation(bool _deactivated) public onlyOwner {
        deactivated = _deactivated;
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

    function listPositionKeys(
        uint256 _start,
        uint256 _end
    ) external view returns (uint256 total, bytes32[] memory keys) {
        total = positionTracker.length();
        keys = positionTracker.list(_start, _end);
    }

    function getPositionInfo(
        bytes32 _positionKey
    ) external view returns (uint8, int24, int24) {
        return positionTracker.getPositionInfo(_positionKey);
    }

    function getReserveAmounts(uint8 _tokenPairId) external view returns(uint256 amount0, uint256 amount1) {
        return reserves.getAmounts(_tokenPairId);
    }

    function getFeesEarned(uint8 _tokenPairId) external view returns(uint256 amount0, uint256 amount1) {
        return feeEarned.getAmounts(_tokenPairId);
    }

    function injectPricinple(uint8 _tokenPairId, uint256 _amount0, uint256 _amount1) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidTokenPair(_tokenPairId);
        _transferIn(tokenPair, _amount0, _amount1);
        reserves.changeAmounts(_tokenPairId, _safeCastUintToInt(_amount0), _safeCastUintToInt(_amount1));
    }

    // deprecated
    function increaseLiquidity(
        bytes32 _positionKey,
        uint256 _amount0Desired,
        uint256 _amount1Desired,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner onlyActivated {
        TokenPair memory tokenPair = _ensureValidPosition(_positionKey);

        _transferIn(tokenPair, _amount0Desired, _amount1Desired);

        (int24 tickLower, int24 tickUpper) = positionTracker.getPositionTicks(
            _positionKey
        );

        LiquidityChangeOutput memory output = _addLiquidity(
            tokenPair,
            tickLower,
            tickUpper,
            _amount0Desired,
            _amount1Desired,
            _amount0Min,
            _amount1Min
        );

        // no need to increase the pool reserves as residual tokens are all refunded

        _refund(msg.sender, tokenPair.token0, _amount0Desired, output.amount0);
        _refund(msg.sender, tokenPair.token1, _amount1Desired, output.amount1);

        emit PositionChanged(
            _positionKey,
            PositionChange.Increase,
            output.amount0,
            output.amount1,
            msg.sender
        );
    }

    function decreaseLiquidity(
        bytes32 _positionKey,
        uint128 _reduction,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidPosition(_positionKey);
        (int24 tickLower, int24 tickUpper) = positionTracker.getPositionTicks(
            _positionKey
        );

        IUniswapV3Pool pool = IUniswapV3Pool(tokenPair.pool);

        LiquidityChangeOutput memory output = _burnWithSlippageCheck(
            pool,
            _reduction,
            tickLower,
            tickUpper,
            _amount0Min,
            _amount1Min
        );

        // directly send to liqiudity owner, perform uint128 check
        _collect(
            pool,
            msg.sender,
            tickLower,
            tickUpper,
            _toU128(output.amount0),
            _toU128(output.amount1)
        );

        // no need to update the pool reserves as residual tokens are all refunded

        emit PositionChanged(
            _positionKey,
            PositionChange.Descrese,
            output.amount0,
            output.amount1,
            msg.sender
        );
    }

    /// @notice Collects all the fees associated with provided liquidity
    function batchCollectFees(
        bytes32[] calldata _positionKeys
    ) external onlyLiquidityOwner {
        uint256 length = _positionKeys.length;
        for (uint256 i = 0; i < length; ) {
            TokenPair memory tokenPair = _ensureValidPosition(_positionKeys[i]);
            (int24 tickLower, int24 tickUpper) = positionTracker
                .getPositionTicks(_positionKeys[i]);

            IUniswapV3Pool pool = IUniswapV3Pool(tokenPair.pool);

            (uint128 fee0, uint128 fee1) = _prepareFeeForCollection(
                tokenPair.id,
                pool,
                tickLower,
                tickUpper,
                _positionKeys[i]
            );
            _collect(pool, msg.sender, tickLower, tickUpper, fee0, fee1);

            unchecked {
                ++i;
            }
        }
    }

    function rebalanceClosePosition(
        bytes32 _positionKey,
        uint256 _amount0Min,
        uint256 _amount1Min,
        bool _compoundFee
    ) external onlyBalancer {
        TokenPair memory tokenPair = _ensureValidPosition(_positionKey);
        (uint256 fee0, uint256 fee1, uint128 amount0Collected, uint128 amount1Collected) = _closePosition(
            tokenPair.id,
            IUniswapV3Pool(tokenPair.pool),
            _positionKey,
            _amount0Min,
            _amount1Min,
            address(this)
        );

        if (!_compoundFee) {
            IERC20(tokenPair.token0).safeTransfer(liquidityOwner, fee0);
            IERC20(tokenPair.token1).safeTransfer(liquidityOwner, fee1);
        }

        // token stays in the contract
        reserves.changeAmounts(tokenPair.id, amount0Collected, amount1Collected);
    }

    function closePosition(
        bytes32 _positionKey,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidPosition(_positionKey);
        _closePosition(
            tokenPair.id,
            IUniswapV3Pool(tokenPair.pool),
            _positionKey,
            _amount0Min,
            _amount1Min,
            msg.sender
        );
    }

    function rebalance1For0(
        RebalanceParams calldata _params
    ) external onlyBalancer onlyActivated {
        return _rebalance(_params, false);
    }

    function rebalance0For1(
        RebalanceParams calldata _params
    ) external onlyBalancer onlyActivated {
        return _rebalance(_params, true);
    }

    function _add(uint256 _num, int256 _val) internal pure returns (uint256) {
        if (_val >= 0) {
            return _num + uint256(_val);
        }
        return _num - uint256(-_val);
    }

    function _swap(
        RebalanceParams calldata _params,
        bool _zeroForOne,
        TokenPair memory _tokenPair
    ) internal returns(int256 amount0Delta, int256 amount1Delta) {
        bytes memory preSwapBytes = _preSwapBytes(
            _params,
            _tokenPair,
            _zeroForOne
        );

        if (_zeroForOne) {
            IERC20(_tokenPair.token0).approve(
                address(liquiditySwap),
                _params.amount0
            );
            (amount0Delta, amount1Delta) = liquiditySwap.swapWithSearch0For1(
                _tokenPair.pool,
                _params.sqrtPriceLimitX96,
                _params.searchRange,
                preSwapBytes
            );
            require(amount0Delta < 0 && amount1Delta > 0, "b2");
        } else {
            IERC20(_tokenPair.token1).approve(
                address(liquiditySwap),
                _params.amount1
            );

            (amount0Delta, amount1Delta) = liquiditySwap.swapWithSearch1For0(
                _tokenPair.pool,
                _params.sqrtPriceLimitX96,
                _params.searchRange,
                preSwapBytes
            );

            require(amount0Delta > 0 && amount1Delta < 0, "b1");
        }
    }

    function _rebalance(
        RebalanceParams calldata _params,
        bool _zeroForOne
    ) internal {
        TokenPair memory tokenPair = _ensureValidTokenPair(_params.tokenPairId);

        // ensure we are not over spending the allocated reserves
        (uint256 reserve0, uint256 reserve1) = reserves.getAmounts(tokenPair.id);
        if (reserve0 < _params.amount0 || reserve1 < _params.amount1) {
            revert RebalanceExceedReserve(
                reserve0, reserve1, _params.amount0, _params.amount1
            );
        }

        (int256 amount0Delta, int256 amount1Delta) = _swap(_params, _zeroForOne, tokenPair);

        reserve0 = _add(reserve0, amount0Delta);
        reserve1 = _add(reserve1, amount1Delta);

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
                _add(_params.amount0, amount0Delta),
                _add(_params.amount1, amount1Delta)
            );

            emit PositionChanged(
                positionKey,
                PositionChange.Increase,
                output.amount0,
                output.amount1,
                msg.sender
            );
        } else {
            RebalanceCalParams memory params = RebalanceCalParams({
                amount0Desired: _add(_params.amount0, amount0Delta),
                amount1Desired: _add(_params.amount1, amount1Delta),
                amount0Min: 0,
                amount1Min: 0
            });
            params.amount0Min = LibPercentageMath.deductRate(params.amount0Desired, _params.maxMintSlippageRate);
            params.amount1Min = LibPercentageMath.deductRate(params.amount1Desired, _params.maxMintSlippageRate);

            output = _addLiquidity(
                tokenPair,
                _params.tickLower,
                _params.tickUpper,
                params.amount0Desired,
                params.amount1Desired,
                params.amount0Min,
                params.amount1Min
            );

            positionKey = positionTracker.tryInsertNewPosition(
                tokenPair.id,
                _params.tickLower,
                _params.tickUpper
            );

            emit PositionChanged(
                positionKey,
                PositionChange.Create,
                output.amount0,
                output.amount1,
                msg.sender
            );
        }

        reserves.setAmounts(tokenPair.id, reserve0 - output.amount0, reserve1 - output.amount1);
    }

    function escapeHatchBurn(
        address _pool,
        uint128 _liqiudity,
        int24 tickLower,
        int24 tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external onlyBalancer onlyDeactivated {
        _burnWithSlippageCheck(
            IUniswapV3Pool(_pool),
            _liqiudity,
            tickLower,
            tickUpper,
            _amount0Min,
            _amount1Min
        );
    }

    function escapeHatchCollect(
        address _pool,
        int24 tickLower,
        int24 tickUpper
    ) external onlyBalancer onlyDeactivated {
        _collect(
            IUniswapV3Pool(_pool),
            liquidityOwner,
            tickLower,
            tickUpper,
            UINT128_MAX,
            UINT128_MAX
        );
    }

    function forceWithdraw(uint8 _tokenPairId) external onlyLiquidityOwner onlyDeactivated {
        TokenPair memory tokenPair = _ensureValidTokenPair(_tokenPairId);
        _withdraw(tokenPair);
    }

    function withdraw(uint8 _tokenPairId) external onlyLiquidityOwner {
        TokenPair memory tokenPair = _ensureValidTokenPair(_tokenPairId);
        _withdraw(tokenPair);

        reserves.setAmounts(_tokenPairId, 0, 0);
    }

    function _withdraw(TokenPair memory _tokenPair) internal {
        address lpOwner = liquidityOwner;

        uint256 amount0 = IERC20(_tokenPair.token0).balanceOf(address(this));
        IERC20(_tokenPair.token0).safeTransfer(lpOwner, amount0);

        uint256 amount1 = IERC20(_tokenPair.token1).balanceOf(address(this));
        IERC20(_tokenPair.token1).safeTransfer(lpOwner, amount1);

        emit RemainingFundsWithdrawn(lpOwner, amount0, amount1);
    }

    function _toU128(uint256 _num) internal pure returns (uint128 v) {
        v = uint128(_num);
        if (uint256(v) != _num) {
            revert TooMuchLiquidityToWithdraw(_num);
        }
    }

    function _closePosition(
        uint8 _tokenPairId,
        IUniswapV3Pool _pool,
        bytes32 _positionKey,
        uint256 _amount0Min,
        uint256 _amount1Min,
        address _recipient
    ) internal returns (uint128 fee0, uint128 fee1, uint128 amount0Colleted, uint128 amount1Collected) {
        (int24 tickLower, int24 tickUpper) = positionTracker.getPositionTicks(
            _positionKey
        );

        (fee0, fee1) = _prepareFeeForCollection(
            _tokenPairId,
            _pool,
            tickLower,
            tickUpper,
            _positionKey
        );
        uint128 liquidity = _positionLiquidity(_pool, tickLower, tickUpper);

        _burnWithSlippageCheck(
            _pool,
            liquidity,
            tickLower,
            tickUpper,
            _amount0Min,
            _amount1Min
        );

        (amount0Colleted, amount1Collected) = _collect(
            _pool,
            _recipient,
            tickLower,
            tickUpper,
            UINT128_MAX,
            UINT128_MAX
        );

        positionTracker.remove(_positionKey);

        emit PositionChanged(
            _positionKey,
            PositionChange.Closed,
            amount0Colleted - fee0,
            amount1Collected - fee1,
            msg.sender
        );
    }

    function _prepareFeeForCollection(
        uint8 _tokenPairId,
        IUniswapV3Pool _pool,
        int24 _tickLower,
        int24 _tickUpper,
        bytes32 _positionKey
    ) internal returns (uint128 fee0, uint128 fee1) {
        _pool.burn(_tickLower, _tickUpper, 0);

        (fee0, fee1) = _tokensOwned(_pool, _tickLower, _tickUpper);

        uint128 protocolFee0 = _calculateProtocolFee(fee0);
        uint128 protocolFee1 = _calculateProtocolFee(fee1);

        // send protocol fee to contract owner
        if (protocolFee0 != 0 || protocolFee1 != 0) {
            _collect(
                _pool,
                owner(),
                _tickLower,
                _tickUpper,
                protocolFee0,
                protocolFee1
            );

            fee0 -= protocolFee0;
            fee1 -= protocolFee1;
        }

        // cast will be safe because uint128 will not overflow when cast to int256
        feeEarned.changeAmounts(_tokenPairId, fee0, fee1);

        emit FeesCollected(
            _positionKey,
            fee0,
            fee1,
            protocolFee0,
            protocolFee1
        );
    }

    function _calculateProtocolFee(
        uint128 amount
    ) internal view returns (uint128) {
        return (amount * operationalParams.protocolFeeRate) / 1000;
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

        emit InjectedPriciple(_tokenPair.id, _amount0, _amount1);
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
        output = _addLiquidity(
            _tokenPair,
            _params.tickLower,
            _params.tickUpper,
            _amount0,
            _amount1,
            LibPercentageMath.deductRate(_amount0, _params.maxMintSlippageRate),
            LibPercentageMath.deductRate(_amount0, _params.maxMintSlippageRate)
        );
    }

    function _safeCastUintToInt(uint256 u) public pure returns (int256) {
        require(u <= uint256(type(int256).max), "OF-I256");
        return int256(u);
    }
}
