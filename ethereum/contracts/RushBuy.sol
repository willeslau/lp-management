// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v3-core/contracts/libraries/SqrtPriceMath.sol";

import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ISwapUtil, SwapParams, Swapper} from "./SwapUtil.sol";

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
contract RushBuy is
    UUPSUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    uint160 constant public RATIO_SQRT_BASE = 10000;
    uint128 constant public ONE_ETHER = uint128(1 ether);
    uint256 constant Q96 = 2 ** 96;
    uint256 constant Q192 = 2 ** 192;

    struct Position {
        address pool;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    struct SwapState {
        bool zeroForOne;

        int24 tickLower;
        int24 tickUpper;

        uint160 priceRatioLowerX96;
        uint160 priceRatioX96;
        uint160 priceRatioUpperX96;

        uint160 priceLimitSqrtX96;
        uint256 priceLimitX96;

        int256 amountIn;
        int256 amountOut;

        uint256 rX96;
    }

    struct BuyParams {
        address pool;
        uint8 decimal0;
        uint8 decimal1;
        address token0;
        address token1;
        uint160 slippageProtectionSqrt;
        uint160 lowerBoundSqrt;
        uint160 upperBoundSqrt;
        int256 minOutPerIn;
    }

    error NoPosition();
    error InvalidPool();
    error NotSupported();
    error PriceLimitTooBig();
    error PriceLimitTooSmall();
    error InvariantBroken(string error);
    error Amount0ExceedMax();
    error Amount1ExceedMax();
    error UniswapCallFailed(string marker, bytes reason);
    error NotUniswapPool(address pool);
    error HasPosition(address pool, int24 tickLower, int24 tickUpper);

    Position public position;
    ISwapUtil public swapUtil;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _swapUtil
    ) external initializer {
        __Ownable_init();
        swapUtil = ISwapUtil(_swapUtil);
    }

    function validateBuyParams(BuyParams calldata _buyParams, uint24 _fee) external view returns(SwapState memory swap) {
        IUniswapV3Pool pool = IUniswapV3Pool(_buyParams.pool);

        if (pool.token0() != _buyParams.token0) revert InvalidPool();
        if (pool.token1() != _buyParams.token1) revert InvalidPool();
        if (pool.fee() != _fee) revert InvalidPool();

        if (IERC20Metadata(_buyParams.token0).decimals() != _buyParams.decimal0) revert InvalidPool();
        if (IERC20Metadata(_buyParams.token1).decimals() != _buyParams.decimal1) revert InvalidPool();

        return calculateSwapState(_buyParams);
    }

    function calculateSwapState(BuyParams calldata _buyParams) public view returns(SwapState memory swapState) {
        (swapState.priceRatioX96, ) = _slot0(_buyParams.pool);

        {
            uint160 priceRatioLowerX96 = swapState.priceRatioX96 * _buyParams.lowerBoundSqrt / RATIO_SQRT_BASE;
            uint160 priceRatioUpperX96 = swapState.priceRatioX96 * _buyParams.upperBoundSqrt / RATIO_SQRT_BASE;

            int24 tickSpacing = IUniswapV3Pool(_buyParams.pool).tickSpacing();

            swapState.tickLower = _nearestTick(priceRatioLowerX96, tickSpacing);
            swapState.tickUpper = _nearestTick(priceRatioUpperX96, tickSpacing);
        }

        swapState.priceRatioLowerX96 = TickMath.getSqrtRatioAtTick(swapState.tickLower);
        swapState.priceRatioUpperX96 = TickMath.getSqrtRatioAtTick(swapState.tickUpper);

        uint256 balance0 = IERC20(_buyParams.token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_buyParams.token1).balanceOf(address(this));

        if (balance0 == 0 && balance1 != 0) swapState.zeroForOne = false;
        else if (balance0 != 0 && balance1 == 0) swapState.zeroForOne = true;
        else revert NotSupported();

        _updateTargetRX96(swapState);

        if (swapState.zeroForOne) {
            if (_buyParams.slippageProtectionSqrt > RATIO_SQRT_BASE) revert PriceLimitTooBig();
        } else {
            if (_buyParams.slippageProtectionSqrt < RATIO_SQRT_BASE) revert PriceLimitTooSmall();
        }

        _updateSwapAmount(swapState, _buyParams, balance0, balance1);
    }

    function buy(
        BuyParams calldata _params
    ) external onlyOwner {
        if (position.liquidity != 0) revert HasPosition(position.pool, position.tickLower, position.tickUpper);

        SwapState memory swapState = calculateSwapState(_params);

        SwapParams memory swap = SwapParams({
            swapper: Swapper.UniswapPool,
            zeroForOne: swapState.zeroForOne,
            priceSqrtX96Limit: swapState.priceLimitSqrtX96,
            amountOutMin: swapState.amountOut,
            amountIn: swapState.amountIn
        });

        position.pool = _params.pool;

        int256 amount0;
        int256 amount1;

        if (swap.zeroForOne) {
            IERC20(_params.token0).approve(address(swapUtil), uint256(swapState.amountIn));
            (amount0, amount1) = swapUtil.swap(
                _params.pool,
                _params.token0,
                swap
            );
        } else {
            IERC20(_params.token1).approve(address(swapUtil), uint256(swapState.amountIn));
            (amount0, amount1) = swapUtil.swap(
                _params.pool,
                _params.token1,
                swap
            );
        }

        _addLiquidity(IUniswapV3Pool(_params.pool), swapState, _params);

    }

    function closePosition() external onlyOwner {
        Position memory pos = position;

        if (pos.liquidity == 0) revert NoPosition();

        IUniswapV3Pool pool = IUniswapV3Pool(pos.pool);
        pool.burn(pos.tickLower, pos.tickUpper, pos.liquidity);

        pool.collect(
            owner(),
            pos.tickLower,
            pos.tickUpper,
            type(uint128).max,
            type(uint128).max
        );

        position.liquidity = 0;
    }

    function withdraw(address _token) external onlyOwner() {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
    }

    function pancakeV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    // ==================== Internal Methods ====================

    function _mintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) internal {
        if (msg.sender != position.pool) revert NotUniswapPool(msg.sender);

        (address token0, address token1) = abi.decode(data, (address, address));

        if (amount0Owed > 0)
            IERC20(token0).safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0)
            IERC20(token1).safeTransfer(msg.sender, amount1Owed);
    }

    /**
     *  Used to control authorization of upgrade methods
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        newImplementation; // silence the warning
    }

    function _updateSwapAmount(SwapState memory _swapState, BuyParams calldata _buyParams, uint256 _amount0, uint256 _amount1) internal pure {
        uint256 num1 = _amount1 * _swapState.rX96;
        uint256 num2 = _amount0 * Q96;

        _swapState.priceLimitSqrtX96 = _swapState.priceRatioX96 * _buyParams.slippageProtectionSqrt / RATIO_SQRT_BASE;
        uint256 priceX96 = _calculatePrice(_swapState.priceLimitSqrtX96, _buyParams.decimal0, _buyParams.decimal1);

        // uint256 den = Q96 + FullMath.mulDiv(priceX96, _swapState.rX96, Q96);
        uint256 den = Q96 + priceX96 * _swapState.rX96 / Q96;

        uint256 delta0;
        if (_swapState.zeroForOne) {
            if (num1 > num2) revert InvariantBroken("num1 should be <= num2");
            delta0 = (num2 - num1) / den;
        } else {
            if (num2 > num1) revert InvariantBroken("num2 should be <= num1");
            delta0 = (num1 - num2) / den;
        }

        uint256 delta1 = FullMath.mulDiv(delta0, priceX96, Q96);

        if (delta0 > uint256(type(int256).max)) revert Amount0ExceedMax();
        if (delta1 > uint256(type(int256).max)) revert Amount1ExceedMax();

        if (_swapState.zeroForOne) {
            _swapState.amountIn = int256(delta0);
            _swapState.amountOut = int256(delta1);
        } else {
            _swapState.amountIn = int256(delta1);
            _swapState.amountOut = int256(delta0);
        }

        _swapState.priceLimitX96 = priceX96;
    }

    function _calculatePrice(uint256 _priceLimitSqrtX96, uint8 decimal0, uint8 decimal1) internal pure returns(uint256 priceX96) {
        priceX96 = FullMath.mulDiv(_priceLimitSqrtX96, _priceLimitSqrtX96, Q96);

        if (decimal0 > decimal1) {
            priceX96 *= 10 ** (decimal0 - decimal1);
        } else {
            priceX96 /= 10 ** (decimal1 - decimal0);
        }
    }

    function _updateTargetRX96(SwapState memory _swapState) internal pure {
        uint256 targetToken0 = SqrtPriceMath.getAmount0Delta(_swapState.priceRatioX96, _swapState.priceRatioUpperX96, ONE_ETHER, true);
        uint256 targetToken1 = SqrtPriceMath.getAmount1Delta(_swapState.priceRatioLowerX96, _swapState.priceRatioX96, ONE_ETHER, true);
        _swapState.rX96 = FullMath.mulDiv(Q96, targetToken0, targetToken1);
    }

    /// In favour of wider tick if tick is negative, narrower tick if tick is positive
    function _nearestTick(uint160 _ratioSqrt, int24 _tickSpacing) internal pure returns(int24) {
        return TickMath.getTickAtSqrtRatio(_ratioSqrt) / _tickSpacing * _tickSpacing;
    }

    function _slot0(
        address _pool
    ) internal view returns (uint160 sqrtPriceX96, int24 tick) {
        // using low level call instead as we want to parse the data ourselves.
        // why do we do this? Because we want to support both uniswap and pancakeswap
        // uniswap.slot0.fee is uint8 but pancakeswap is u32
        (bool success, bytes memory data) = _pool.staticcall(
            abi.encodeWithSignature("slot0()")
        );
        require(success, "sf");

        (sqrtPriceX96, tick) = abi.decode(data, (uint160, int24));
    }

    /// @notice Add liquidity to an initialized pool
    function _addLiquidity(
        IUniswapV3Pool _pool,
        SwapState memory _swapState,
        BuyParams calldata _buyParams
    ) internal {
        (uint160 sqrtPriceX96, ) = _slot0(address(_pool));

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            _swapState.priceRatioLowerX96,
            _swapState.priceRatioUpperX96,
            IERC20(_buyParams.token0).balanceOf(address(this)),
            IERC20(_buyParams.token1).balanceOf(address(this))
        );

        bytes memory m = abi.encode(_buyParams.token0, _buyParams.token1);

        try
            _pool.mint(address(this), _swapState.tickLower, _swapState.tickUpper, liquidity, m)
        returns (uint256, uint256) {
        } catch (bytes memory reason) {
            revert UniswapCallFailed("am", reason);
        }

        position.liquidity = liquidity;
        position.tickLower = _swapState.tickLower;
        position.tickUpper = _swapState.tickUpper;
    }
}
