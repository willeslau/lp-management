// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockUniswapV3Pool is IUniswapV3Pool {
    using SafeERC20 for IERC20;

    address public override factory;
    address public override token0;
    address public override token1;
    uint24 public override fee;
    uint160 public sqrtPriceX96;
    int24 public tick;
    uint128 public override liquidity;
    int24 public override tickSpacing;
    bool public swapCalled;
    uint256 public swapResult;

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        factory = msg.sender;
        tickSpacing = 10; // Default value for testing
        sqrtPriceX96 = 4218481174524931107978693574656; // Default value for testing
        tick = 100; // Default value for testing
        liquidity = 1000000; // Default value for testing
    }

    function setLiquidity(uint128 _liquidity) external {
        liquidity = _liquidity;
    }

    function setSqrtPriceX96(uint160 _sqrtPriceX96) external {
        sqrtPriceX96 = _sqrtPriceX96;
    }

    function setTick(int24 _tick) external {
        tick = _tick;
    }

    function setTickSpacing(int24 _tickSpacing) external {
        tickSpacing = _tickSpacing;
    }

    function setSwapResult(uint256 _result) external {
        swapResult = _result;
    }

    function slot0()
        external
        view
        override
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool)
    {
        return (sqrtPriceX96, tick, 0, 0, 0, 0, false);
    }

    function getPool(
        address,
        address,
        uint24
    ) external view returns (address pool) {
        return address(this);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override returns (int256 amount0, int256 amount1) {
        swapCalled = true;

        if (amountSpecified > 0) {
            if (zeroForOne) {
                amount0 = amountSpecified;
                amount1 = -int256((uint256(amountSpecified) * 990) / 1000); // 0.99 rate for testing
                IERC20(token0).safeTransferFrom(
                    msg.sender,
                    address(this),
                    uint256(amount0)
                );
                IERC20(token1).safeTransfer(recipient, uint256(-amount1));
            } else {
                amount1 = amountSpecified;
                amount0 = -int256((uint256(amountSpecified) * 990) / 1000); // 0.99 rate for testing
                IERC20(token1).safeTransferFrom(
                    msg.sender,
                    address(this),
                    uint256(amount1)
                );
                IERC20(token0).safeTransfer(recipient, uint256(-amount0));
            }
        }
        return (amount0, amount1);
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external {
        if (amount0Owed > 0) {
            IERC20(token0).safeTransferFrom(
                msg.sender,
                address(this),
                amount0Owed
            );
        }
        if (amount1Owed > 0) {
            IERC20(token1).safeTransferFrom(
                msg.sender,
                address(this),
                amount1Owed
            );
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external {
        if (amount0Delta > 0) {
            IERC20(token0).safeTransferFrom(
                msg.sender,
                address(this),
                uint256(amount0Delta)
            );
        }
        if (amount1Delta > 0) {
            IERC20(token1).safeTransferFrom(
                msg.sender,
                address(this),
                uint256(amount1Delta)
            );
        }
    }

    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override returns (uint256 amount0, uint256 amount1) {
        amount0 = uint256(amount);
        amount1 = uint256(amount);
        return (amount0, amount1);
    }

    function positions(
        bytes32 key
    )
        external
        view
        override
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return (liquidity, 0, 0, 0, 0);
    }

    function observe(
        uint32[] calldata
    ) external pure override returns (int56[] memory, uint160[] memory) {
        return (new int56[](0), new uint160[](0));
    }

    function increaseObservationCardinalityNext(
        uint16
    ) external pure override {}

    function initialize(uint160) external pure override {}

    function collect(
        address,
        int24,
        int24,
        uint128,
        uint128
    ) external pure override returns (uint128, uint128) {
        return (0, 0);
    }

    function burn(
        int24,
        int24,
        uint128 amount
    ) external override returns (uint256, uint256) {
        uint256 amount0 = uint256(amount);
        uint256 amount1 = uint256(amount);
        return (amount0, amount1);
    }

    function flash(
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override {}

    function setFeeProtocol(uint8, uint8) external pure override {}

    function collectProtocol(
        address,
        uint128,
        uint128
    ) external pure override returns (uint128, uint128) {
        return (0, 0);
    }

    function feeGrowthGlobal0X128() external pure override returns (uint256) {
        return 0;
    }

    function feeGrowthGlobal1X128() external pure override returns (uint256) {
        return 0;
    }

    function maxLiquidityPerTick() external pure override returns (uint128) {
        return type(uint128).max;
    }

    function observations(
        uint256
    )
        external
        pure
        override
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        )
    {
        return (0, 0, 0, false);
    }

    function protocolFees() external pure override returns (uint128, uint128) {
        return (0, 0);
    }

    function snapshotCumulativesInside(
        int24 tickLower,
        int24 tickUpper
    )
        external
        pure
        override
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        return (0, 0, 0);
    }

    function tickBitmap(int16) external pure override returns (uint256) {
        return 0;
    }

    function ticks(
        int24
    )
        external
        pure
        override
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        )
    {
        return (0, 0, 0, 0, 0, 0, 0, false);
    }
}
