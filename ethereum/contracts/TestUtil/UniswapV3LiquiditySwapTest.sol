// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {LiquiditySwapV3, CompareResult} from '../UniswapV3LiquiditySwap.sol';
import {ILiquiditySwapV3, SearchRange} from "../interfaces/ILiquiditySwap.sol";

interface IUniswapV3LiquidityBytesTest {
    function revertSwapCallback(CompareResult _r, int256 _amount) external returns(bytes memory);

    function decodeSwapRevertData(bytes memory _revert) external returns(CompareResult _r, int256 _amount);
}

contract RevertDataTesting {
    IUniswapV3LiquidityBytesTest public inner;

    constructor() {
        inner = IUniswapV3LiquidityBytesTest(address(new UniswapV3LiquidityBytesTest()));
    }

    function test_Postive() external {
        _testInner(CompareResult.AboveRange, int256(10));
    }

    function test_Negative() external {
        _testInner(CompareResult.AboveRange, int256(-10));
    }

    function test_Zero() external {
        _testInner(CompareResult.AboveRange, int256(0));
    }

    function test_MaxPositive() external {
        _testInner(CompareResult.AboveRange, int256(57896044618658097711785492504343953926634992332820282019728792003956564819967));
    }

    function test_MinNegative() external {
        _testInner(CompareResult.AboveRange, int256(-57896044618658097711785492504343953926634992332820282019728792003956564819968));
    }

    function _testInner(CompareResult _r, int256 _amount) internal {
        try inner.revertSwapCallback(_r, _amount) {}
        catch(bytes memory reason) {
            (CompareResult r, int256 amount) = inner.decodeSwapRevertData(reason);
            require(r == _r, "r not the same");
            require(amount == _amount, "amount not the same");
        }
    }
}

contract UniswapV3LiquidityBytesTest is LiquiditySwapV3 {
    function revertSwapCallback(CompareResult _r, int256 _amount) external pure returns(bytes memory) {
        _revertSwapCallback(_r, _amount);
    }

    function decodeSwapRevertData(bytes memory _revert) external pure returns(CompareResult _r, int256 _amount) {
        return _decodeSwapRevertData(_revert);
    }
}
