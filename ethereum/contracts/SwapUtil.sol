// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {CallbackUtil} from "./Callback.sol";
import {SwapSlippageError} from "./Errors.sol";

enum Swapper {
    UniswapPool
}

struct SwapParams {
    Swapper swapper;
    bool zeroForOne;
    uint160 priceSqrtX96Limit;
    int256 amountOutMin;
    int256 amountIn;
}

interface ISwapUtil {
    function swap(
        address _pool,
        address _tokenIn,
        SwapParams calldata _params
    ) external returns (int256 amount0Delta, int256 amount1Delta);
}

/// A swap util that supports both:
/// - Swap with uniswap pool directly
/// - Calling external router
///
/// Note the invariants of this contract:
/// - Should not hold any balance of any token after each transaction
contract SwapUtil is CallbackUtil {
    using SafeERC20 for IERC20;

    function _swapCallback(
        int256 _amount0Delta,
        int256 _amount1Delta,
        bytes calldata _data
    ) internal {
        (
            bool zeroForOne,
            address token,
            int256 minAmountOut,
            address payer
        ) = abi.decode(_data, (bool, address, int256, address));

        if (zeroForOne) {
            _ensureWithinSlippage(_amount1Delta, minAmountOut);
            IERC20(token).safeTransferFrom(
                payer,
                msg.sender,
                uint256(_amount0Delta)
            );
        } else {
            _ensureWithinSlippage(_amount0Delta, minAmountOut);
            IERC20(token).safeTransferFrom(
                payer,
                msg.sender,
                uint256(_amount1Delta)
            );
        }
    }

    function uniswapV3SwapCallback(
        int256 _amount0Delta,
        int256 _amount1Delta,
        bytes calldata _data
    ) external checkCallbackFrom {
        _swapCallback(_amount0Delta, _amount1Delta, _data);
    }

    function pancakeV3SwapCallback(
        int256 _amount0Delta,
        int256 _amount1Delta,
        bytes calldata _data
    ) external checkCallbackFrom {
        _swapCallback(_amount0Delta, _amount1Delta, _data);
    }

    function swap(
        address _pool,
        address _tokenIn,
        SwapParams calldata _params
    ) external returns (int256 amount0Delta, int256 amount1Delta) {
        if (_params.swapper == Swapper.UniswapPool) {
            (amount0Delta, amount1Delta) = _directPoolSwap(
                _pool,
                _tokenIn,
                _params
            );
        } else {
            revert("NS");
        }
    }

    function _ensureWithinSlippage(
        int256 _amountOut,
        int256 _minAmountOut
    ) internal pure {
        // this is because _amountOut is negative from uniswap
        if (-_amountOut < _minAmountOut)
            revert SwapSlippageError(_amountOut, _minAmountOut);
    }

    function _directPoolSwap(
        address _pool,
        address _tokenIn,
        SwapParams calldata _params
    ) internal returns (int256, int256) {
        _expectCallbackFrom(_pool);

        bytes memory callback = abi.encode(
            _params.zeroForOne,
            _tokenIn,
            _params.amountOutMin,
            msg.sender
        );
        (int256 a0, int256 a1) = IUniswapV3Pool(_pool).swap(
            msg.sender,
            _params.zeroForOne,
            _params.amountIn,
            _params.priceSqrtX96Limit,
            callback
        );

        _invalidateCallback();

        // reverse the sign as it is relative to the users
        return (-a0, -a1);
    }
}
