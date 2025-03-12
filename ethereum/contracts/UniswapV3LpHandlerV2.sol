// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@uniswap/v3-periphery/contracts/libraries/PositionKey.sol";
import "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/base/Multicall.sol";
import "@uniswap/v3-periphery/contracts/base/PeripheryValidation.sol";
import "@uniswap/v3-periphery/contracts/base/SelfPermit.sol";
import "@uniswap/v3-periphery/contracts/base/PoolInitializer.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./UniswapV3SwapPool.sol";
import {LibPercentageMath} from "./RateMath.sol";

struct RebalanceParams {
    uint256 tokenId;
    uint256 amount0WithdrawMin;
    uint256 amount1WithdrawMin;
    uint16 swapSlippage;
    uint256 newAmount0;
    uint256 newAmount1;
    int24 tickLower;
    int24 tickUpper;
}

// details about the uniswap position
struct Position {
    uint80 poolId;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
    uint128 tokensOwed0;
    uint128 tokensOwed1;
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

struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
}

/// @title Uniswap V3 Position Manager
/// @notice Manages Uniswap V3 liquidity positions
contract UniswapV3Manager is
    Multicall,
    UniswapV3SwapPool,
    PoolInitializer,
    LiquidityManagement,
    PeripheryValidation,
    SelfPermit
{
    using SafeERC20 for IERC20;

    error InvalidTokenId();
    error InsufficientLiquidity();
    error PriceSlippageCheck();
    error InvalidCollectAmount();
    error PositionNotCleared();
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

    /// @notice Emitted when liquidity is increased for a position NFT
    /// @dev Also emitted when a token is minted
    /// @param tokenId The ID of the token for which liquidity was increased
    /// @param liquidity The amount by which liquidity for the NFT position was increased
    /// @param amount0 The amount of token0 that was paid for the increase in liquidity
    /// @param amount1 The amount of token1 that was paid for the increase in liquidity
    event IncreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when liquidity is decreased for a position NFT
    /// @param tokenId The ID of the token for which liquidity was decreased
    /// @param liquidity The amount by which liquidity for the NFT position was decreased
    /// @param amount0 The amount of token0 that was accounted for the decrease in liquidity
    /// @param amount1 The amount of token1 that was accounted for the decrease in liquidity
    event DecreaseLiquidity(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when tokens are collected for a position NFT
    /// @dev The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior
    /// @param tokenId The ID of the token for which underlying tokens were collected
    /// @param recipient The address of the account that received the collected tokens
    /// @param amount0 The amount of token0 owed to the position that was collected
    /// @param amount1 The amount of token1 owed to the position that was collected
    event Collect(
        uint256 indexed tokenId,
        address recipient,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when a new position is created
    /// @param tokenId The ID of the token for which position was created
    /// @param liquidity The amount of liquidity provided for the position
    /// @param amount0 The amount of token0 used to create the position
    /// @param amount1 The amount of token1 used to create the position
    event PositionCreated(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );
    /// @notice Emitted when a position is rebalanced to a new tick range
    /// @param tokenId The ID of the token for which position was rebalanced
    /// @param liquidity The amount of liquidity in the rebalanced position
    /// @param amount0 The amount of token0 used to create the position
    /// @param amount1 The amount of token1 used to create the position
    /// @param tickLower The new lower tick of the position
    /// @param tickUpper The new upper tick of the position
    event PositionRebalanced(
        uint256 indexed tokenId,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1,
        int24 tickLower,
        int24 tickUpper
    );
    /// @notice Emitted when fees are collected from a position
    /// @param tokenId The ID of the token for which fees were collected
    /// @param fee0 The amount of token0 fees that were collected
    /// @param fee1 The amount of token1 fees that were collected
    event FeesCollected(uint256 indexed tokenId, uint256 fee0, uint256 fee1);

    /// @dev IDs of pools assigned by this contract
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The token ID position data
    mapping(uint256 => Position) private _positions;

    // @dev The list of configuration parameters for liquidity operations
    OperationParams public operationalParams;

    /// @notice The owner of liquidity. This address has the permission to close positions
    address public liquidityOwner;
    /// @notice The address that can rebalance the liquidity positions
    address public balancer;

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    uint80 private _nextPoolId = 1;

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

    constructor(
        address _factory,
        address _WETH9,
        address _liquidityOwner,
        address _balancer
    ) PeripheryImmutableState(_factory, _WETH9) UniswapV3SwapPool(_factory) {
        setLiquidityOwner(_liquidityOwner);
        setBalancer(_balancer);

        // max slippage is 3%
        operationalParams.maxMintSlippageRate = 30;
        operationalParams.isCompoundFee = true;
        operationalParams.protocolFeeRate = 50;
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

    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        if (position.poolId == 0) {
            revert InvalidTokenId();
        }

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @dev Caches a pool key
    function cachePoolKey(
        address pool,
        PoolAddress.PoolKey memory poolKey
    ) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
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
        _mint(token0, token1, fee, tickLower, tickUpper, amount0, amount1);
    }

    function increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external payable onlyLiquidityOwner {
        Position storage position = _positions[tokenId];
        (, PoolAddress.PoolKey memory poolKey) = _getPoolInfo(position);

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

        (, uint256 amount0Minted, uint256 amount1Minted) = _increaseLiquidity(
            tokenId,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );

        _refund(poolKey.token0, amount0Desired, amount0Minted);
        _refund(poolKey.token1, amount1Desired, amount1Minted);
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable onlyLiquidityOwner {
        Position storage position = _positions[tokenId];
        (, PoolAddress.PoolKey memory poolKey) = _getPoolInfo(position);
        (uint256 amount0, uint256 amount1) = _decreaseLiquidity(
            tokenId,
            liquidity,
            amount0Min,
            amount1Min
        );

        _sendTo(msg.sender, poolKey.token0, amount0);
        _sendTo(msg.sender, poolKey.token1, amount1);
    }

    /// @notice Collects all the fees associated with provided liquidity
    /// @param tokenIds The ids of the token to mint in uniswap v3
    function batchCollectFees(
        uint256[] calldata tokenIds
    ) external onlyLiquidityOwner {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ) {
            collectAllFees(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @param tokenId The id of the token to mint in uniswap v3
    function collectAllFees(uint256 tokenId) public onlyLiquidityOwner {
        (
            uint256 amount0,
            uint256 amount1,
            PoolAddress.PoolKey memory poolKey
        ) = _collect(
                tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            );
        uint256 protocolFee0 = _calculateProtocolFee(amount0);
        uint256 protocolFee1 = _calculateProtocolFee(amount1);

        if (protocolFee0 != 0) {
            _sendTo(liquidityOwner, poolKey.token0, protocolFee0);
        }

        if (protocolFee1 != 0) {
            _sendTo(liquidityOwner, poolKey.token1, protocolFee1);
        }

        _sendTo(msg.sender, poolKey.token0, amount0 - protocolFee0);
        _sendTo(msg.sender, poolKey.token1, amount1 - protocolFee1);
        emit FeesCollected(tokenId, amount0, amount1);
    }

    function burn(uint256 tokenId) external onlyLiquidityOwner {
        Position storage position = _positions[tokenId];
        if (
            position.liquidity != 0 ||
            position.tokensOwed0 != 0 ||
            position.tokensOwed1 != 0
        ) revert PositionNotCleared();
        delete _positions[tokenId];
    }

    function rebalance(RebalanceParams calldata params) external onlyBalancer {
        _validateTickRange(params.tickLower, params.tickUpper);

        Position memory position = _positions[params.tokenId];
        if (position.poolId == 0) {
            revert InvalidTokenId();
        }

        if (position.liquidity == 0) {
            revert InsufficientLiquidity();
        }

        (, PoolAddress.PoolKey memory poolKey) = _getPoolInfo(position);

        // 1. swap
        _trySwap(
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tokensOwed0,
            position.tokensOwed1,
            params.newAmount0,
            params.newAmount1,
            params.swapSlippage
        );

        // 2. add new liquidity
        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = _mint(
                poolKey.token0,
                poolKey.token1,
                poolKey.fee,
                params.tickLower,
                params.tickUpper,
                params.newAmount0,
                params.newAmount1
            );

        // update tokenId to original one
        _nextId--;
        _positions[params.tokenId] = _positions[tokenId];
        delete _positions[tokenId];

        emit PositionRebalanced(
            params.tokenId,
            liquidity,
            amount0,
            amount1,
            params.tickLower,
            params.tickUpper
        );
    }

    function collectFeesAndReduceLiquidity(
        uint256 tokenId,
        uint256 amount0Min,
        uint256 amount1Min
    ) external onlyBalancer {
        Position memory position = _positions[tokenId];
        if (position.poolId == 0) {
            revert InvalidTokenId();
        }

        if (position.liquidity == 0) {
            revert InsufficientLiquidity();
        }

        // collect fee
        _collect(tokenId, address(this), type(uint128).max, type(uint128).max);

        _decreaseLiquidity(tokenId, position.liquidity, amount0Min, amount1Min);
    }

    function _calculateProtocolFee(
        uint256 amount
    ) internal view returns (uint256) {
        return (amount * operationalParams.protocolFeeRate) / 1000;
    }

    function _validateTickRange(
        int24 _tickLower,
        int24 _tickUpper
    ) internal pure {
        if (_tickLower >= _tickUpper) {
            revert InvalidTickRange(_tickLower, _tickUpper);
        }
    }

    /// @dev Updates position's fee growth and tokens owed
    function _updatePositionFeeGrowth(
        Position storage position,
        IUniswapV3Pool pool,
        uint128 positionLiquidity
    )
        internal
        returns (
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128
        )
    {
        bytes32 positionKey = PositionKey.compute(
            address(this),
            position.tickLower,
            position.tickUpper
        );

        (, feeGrowthInside0LastX128, feeGrowthInside1LastX128, , ) = pool
            .positions(positionKey);

        position.tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                positionLiquidity,
                FixedPoint128.Q128
            )
        );
        position.tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                positionLiquidity,
                FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
    }

    /// @dev Gets pool instance and pool key for a position
    function _getPoolInfo(
        Position memory position
    )
        internal
        view
        returns (IUniswapV3Pool pool, PoolAddress.PoolKey memory poolKey)
    {
        poolKey = _poolIdToPoolKey[position.poolId];
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
    }

    function _mint(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        internal
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        MintParams memory params = MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired
        });

        (uint256 amount0Min, uint256 amount1Min) = _calculateMinAmounts(
            params.amount0Desired,
            params.amount1Desired
        );
        AddLiquidityParams memory addParams = _setupAddLiquidityParams(
            params,
            amount0Min,
            amount1Min
        );

        tokenId = _nextId++;
        IUniswapV3Pool pool;
        (liquidity, amount0, amount1, pool) = addLiquidity(addParams);

        bytes32 positionKey = PositionKey.compute(
            address(this),
            params.tickLower,
            params.tickUpper
        );
        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            ,

        ) = pool.positions(positionKey);

        uint80 poolId = cachePoolKey(
            address(pool),
            PoolAddress.PoolKey({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee
            })
        );

        _createPosition(
            tokenId,
            poolId,
            params.tickLower,
            params.tickUpper,
            liquidity,
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128
        );

        emit PositionCreated(tokenId, liquidity, amount0, amount1);
    }

    function _calculateMinAmounts(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (uint256 amount0Min, uint256 amount1Min) {
        uint16 maxMintSlippageRate = operationalParams.maxMintSlippageRate;
        amount0Min =
            amount0Desired -
            LibPercentageMath.multiply(amount0Desired, maxMintSlippageRate);
        amount1Min =
            amount1Desired -
            LibPercentageMath.multiply(amount1Desired, maxMintSlippageRate);
    }

    function _createPosition(
        uint256 tokenId,
        uint80 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128
    ) internal {
        _positions[tokenId] = Position({
            poolId: poolId,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
    }

    function _setupAddLiquidityParams(
        MintParams memory params,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal view returns (AddLiquidityParams memory) {
        return
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min
            });
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
            amountOutMinimum = _calculateAmountOutMinimum(
                _target1,
                _reserve1,
                _slippage
            );
            isToken0ToToken1 = true;
        } else if (_reserve0 < _target0 && _reserve1 > _target1) {
            amountIn = _reserve1 - _target1;
            amountOutMinimum = _calculateAmountOutMinimum(
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

    function _calculateAmountOutMinimum(
        uint256 target,
        uint256 reserve,
        uint16 slippage
    ) private pure returns (uint256) {
        return ((target - reserve) * (1000 - slippage)) / 1000;
    }

    function _increaseLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        Position storage position = _positions[tokenId];
        (
            IUniswapV3Pool pool,
            PoolAddress.PoolKey memory poolKey
        ) = _getPoolInfo(position);

        (liquidity, amount0, amount1, ) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: address(this)
            })
        );

        _updatePositionFeeGrowth(position, pool, position.liquidity);
        position.liquidity += liquidity;

        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    function _decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0) {
            revert InsufficientLiquidity();
        }

        Position storage position = _positions[tokenId];

        uint128 positionLiquidity = position.liquidity;
        if (positionLiquidity < liquidity) {
            revert InsufficientLiquidity();
        }

        (IUniswapV3Pool pool, ) = _getPoolInfo(position);
        (amount0, amount1) = pool.burn(
            position.tickLower,
            position.tickUpper,
            liquidity
        );

        if (amount0 < amount0Min || amount1 < amount1Min) {
            revert PriceSlippageCheck();
        }

        _updatePositionFeeGrowth(position, pool, positionLiquidity);
        position.tokensOwed0 += uint128(amount0);
        position.tokensOwed1 += uint128(amount1);
        position.liquidity = positionLiquidity - liquidity;

        emit DecreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    function _collect(
        uint256 tokenId,
        address recipient,
        uint128 amount0Max,
        uint128 amount1Max
    )
        internal
        returns (
            uint256 amount0,
            uint256 amount1,
            PoolAddress.PoolKey memory poolKey
        )
    {
        if (amount0Max == 0 && amount1Max == 0) {
            revert InvalidCollectAmount();
        }

        recipient = recipient == address(0) ? address(this) : recipient;

        Position storage position = _positions[tokenId];
        IUniswapV3Pool pool;
        (pool, poolKey) = _getPoolInfo(position);

        (uint128 tokensOwed0, uint128 tokensOwed1) = (
            position.tokensOwed0,
            position.tokensOwed1
        );

        if (position.liquidity > 0) {
            pool.burn(position.tickLower, position.tickUpper, 0);
            _updatePositionFeeGrowth(position, pool, position.liquidity);
            tokensOwed0 = position.tokensOwed0;
            tokensOwed1 = position.tokensOwed1;
        }

        (uint128 amount0Collect, uint128 amount1Collect) = (
            amount0Max > tokensOwed0 ? tokensOwed0 : amount0Max,
            amount1Max > tokensOwed1 ? tokensOwed1 : amount1Max
        );

        (amount0, amount1) = pool.collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        position.tokensOwed0 = tokensOwed0 - amount0Collect;
        position.tokensOwed1 = tokensOwed1 - amount1Collect;

        emit Collect(tokenId, recipient, amount0Collect, amount1Collect);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param _recipient The recipient of the funds
    /// @param _tokenAddress The address of the token to send
    /// @param _amount The amount of token
    function _sendTo(
        address _recipient,
        address _tokenAddress,
        uint256 _amount
    ) internal {
        IERC20(_tokenAddress).safeTransfer(_recipient, _amount);
    }

    /// @notice Refund the extract amount not provided to the LP pool back to liquidity owner
    function _refund(
        address _tokenAddress,
        uint256 _amountExpected,
        uint256 _amountActual
    ) internal {
        if (_amountExpected > _amountActual) {
            IERC20(_tokenAddress).forceApprove(address(this), 0);
            IERC20(_tokenAddress).safeTransfer(
                msg.sender,
                _amountExpected - _amountActual
            );
        }
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferFundsAndApprove(
        address _tokenAddress,
        uint256 _amount
    ) internal {
        // transfer tokens to contract
        IERC20(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // Approve the position manager
        IERC20(_tokenAddress).forceApprove(address(this), _amount);
    }
}
