// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ILiquiditySwapV3, SearchRange} from "./interfaces/ILiquiditySwap.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

enum CompareResult {
    BelowRange,
    InRange,
    AboveRange
}

struct SwapCallbackData {
    bool zeroForOne;
    bytes preSwapRawBytes;
}

struct PreSwapParam {
    uint256 amount0;
    uint256 amount1;
    uint160 R_Q96;
    address tokenIn;
}

contract LiquiditySwapV3Debug is IUniswapV3SwapCallback, Ownable {
    using SafeERC20 for IERC20;

    error SwapOutputInvalid(
        bool zeroForOne,
        int256 amount0Delta,
        int256 amount1Delta
    );
    error SwapAmountBothNonPositive(int256 amount0Delta, int256 amount1Delta);
    error NotExpectingCallbackFrom(address expected, address actual);
    error NotExpectingCallback(address sender);
    error ShouldBeNegative(bool zeroForOne, int256 amount0, int256 amount1);
    error NoSolutionFound(uint8 loops);
    error SwapReverted(CompareResult r, int256 amount);
    error InvalidSwapCallbackRevertLength(bytes reason);
    error InvalidSwapCallbackCompareResult(bytes reason, uint8 r);

    error RevertInCallback(int256 amount0Delta, int256 amount1Delta);

    event SwapOk(int256 amount0, int256 amount1, uint8 loops);
    event RevertCatch(CompareResult r, int256 amount1);

    // 0.001
    uint160 public constant REpslon_Q96 = 79228162514264339242811392;
    uint256 constant Q96 = 2 ** 96;
    uint256 constant CALLBACK_REVERT_LEN = 33;

    address private expectingPool;

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 _amount0Delta,
        int256 _amount1Delta,
        bytes calldata _data
    ) external override {
        require(!(_amount0Delta <= 0 && _amount1Delta <= 0), "a");

        address expectCallFrom = expectingPool;

        require(expectCallFrom != address(0), "b");
        require(expectCallFrom == msg.sender, "c");

        // TODO: switch to use encode packed
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));

        require(!data.zeroForOne, "d");

        _handleSwapCallback1For0(
            -_amount0Delta,
            -_amount1Delta,
            data.preSwapRawBytes
        );

        // invalidate cache
        expectCallFrom = address(0);
    }

    function _handleSwapCallback1For0(
        int256 _amount0Delta,
        int256 _amount1Delta,
        bytes memory _data
    ) internal {
        require(_amount0Delta > 0 && _amount1Delta < 0, "e");

        PreSwapParam memory preSwapParams = abi.decode(_data, (PreSwapParam));
        uint256 amount1Delta = uint256(-_amount1Delta);

        _revertSwapCallback(CompareResult.AboveRange, _amount1Delta);
    }

    // function encodePreSwapData(bool _zeroForOne, PreSwapParam calldata _payload) external pure returns(bytes memory) {
    //     bytes memory inner = abi.encode(_payload);
    //     return abi.encode(SwapCallbackData({ zeroForOne: _zeroForOne, preSwapRawBytes: inner}));
    // }

    function justSwap(
        address _pool,
        uint160 _sqrtPriceLimitX96,
        int256 amount1In,
        bytes calldata _preSwapCalldata
    ) external onlyOwner {
        expectingPool = _pool;

        CompareResult r;
        int256 amount0In;

        try
            IUniswapV3Pool(_pool).swap(
                msg.sender,
                false,
                amount1In,
                _sqrtPriceLimitX96,
                _preSwapCalldata
            )
        returns (int256 a0, int256 a1) {
            // callback handling should have reset the cache
            emit SwapOk(a0, a1, 0);
            return;
        } catch (bytes memory reason) {
            (r, amount0In) = _decodeSwapRevertData(reason);

            // if (r == CompareResult.AboveRange) {
            //     int256 hig = amount0In - 1 wei;
            // } else {
            //     int256 low = amount0In + 1 wei;
            // }

            emit RevertCatch(r, amount0In);
        }
    }

    // function _handleSwapCallback0For1(
    //     int256 _amount0Delta,
    //     int256 _amount1Delta,
    //     bytes memory _data
    // ) internal {
    //     if (_amount0Delta > 0 || _amount1Delta < 0) {
    //         revert SwapOutputInvalid(true, _amount0Delta, _amount1Delta);
    //     }

    //     PreSwapParam memory preSwapParams = abi.decode(_data, (PreSwapParam));
    //     uint256 amount0Delta = uint256(-_amount0Delta);

    //     CompareResult r = _isPostSwapROk(
    //         preSwapParams.amount0 - amount0Delta,
    //         preSwapParams.amount1 + uint256(_amount1Delta),
    //         preSwapParams.R_Q96
    //     );

    //     if (r == CompareResult.InRange) {
    //         IERC20(preSwapParams.tokenIn).safeTransferFrom(owner(), msg.sender, amount0Delta);
    //         return;
    //     }

    //     _revertSwapCallback(r, int256(amount0Delta));
    // }

    // function _handleSwapCallback1For0(
    //     int256 _amount0Delta,
    //     int256 _amount1Delta,
    //     bytes memory _data
    // ) internal {
    //     if (_amount0Delta < 0 || _amount1Delta > 0) {
    //         revert SwapOutputInvalid(false, _amount0Delta, _amount1Delta);
    //     }

    //     PreSwapParam memory preSwapParams = abi.decode(_data, (PreSwapParam));
    //     uint256 amount1Delta = uint256(-_amount1Delta);

    //     CompareResult r = _isPostSwapROk(
    //         preSwapParams.amount0 + uint256(_amount0Delta),
    //         preSwapParams.amount1 - amount1Delta,
    //         preSwapParams.R_Q96
    //     );

    //     if (r == CompareResult.InRange) {
    //         IERC20(preSwapParams.tokenIn).safeTransferFrom(owner(), msg.sender, amount1Delta);
    //         return;
    //     }
    //     _revertSwapCallback(r, int256(amount1Delta));
    // }

    function _revertSwapCallback(
        CompareResult _r,
        int256 _amount
    ) internal pure returns (bytes memory) {
        assembly {
            let ptr := mload(0x40)
            mstore8(ptr, _r)
            mstore(add(ptr, 0x01), _amount)
            revert(ptr, CALLBACK_REVERT_LEN)
        }
    }

    function _decodeSwapRevertData(
        bytes memory _revert
    ) internal pure returns (CompareResult r, int256 amount) {
        require(_revert.length == CALLBACK_REVERT_LEN, "LS: 1");

        uint8 f;
        assembly {
            f := byte(0, mload(add(_revert, 0x20)))
            amount := mload(add(_revert, 0x21))
        }

        if (f == 2) {
            r = CompareResult.AboveRange;
        } else if (f == 0) {
            r = CompareResult.BelowRange;
        } else {
            require(false, "LS: 2");
        }
    }

    // function _isPostSwapROk(uint256 _newAmount0, uint256 _newAmount1, uint256 _R_Q96) internal pure returns (CompareResult) {
    //     uint256 r = _divQ96(_newAmount1 * Q96, _newAmount0 * Q96);
    //     uint256 rDelta_Q96 = 0;

    //     if (r < _R_Q96) {
    //         rDelta_Q96 = _divQ96(_R_Q96 - r, _R_Q96);
    //         if (rDelta_Q96 < REpslon_Q96) {
    //             return CompareResult.InRange;
    //         }
    //         return CompareResult.BelowRange;
    //     }

    //     rDelta_Q96 = _divQ96(r - _R_Q96, _R_Q96);
    //     if (rDelta_Q96 < REpslon_Q96) {
    //         return CompareResult.InRange;
    //     }
    //     return CompareResult.AboveRange;
    // }

    // function _divQ96(uint256 a, uint256 b) internal pure returns(uint256) {
    //     return FullMath.mulDiv(a, Q96, b);
    // }
}
