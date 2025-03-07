// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockUniswapV3Pool {
    using SafeERC20 for IERC20;

    address public token0;
    address public token1;
    uint24 public fee;
    uint160 public sqrtPriceX96;
    int24 public tick;
    uint128 public liquidity;
    int24 public tickSpacing;
    bool public swapCalled;
    uint256 public swapResult;

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
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
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool)
    {
        return (sqrtPriceX96, tick, 0, 0, 0, 0, false);
    }

    function getPool(address, address, uint24) external view returns (address pool) {
        return address(this);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        swapCalled = true;

        amount0 = amountSpecified;
        amount1 = amountSpecified;
    }
}
