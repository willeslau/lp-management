// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ISwapUtil, SwapParams, Swapper} from "./SwapUtil.sol";

struct SellParams {
    Swapper swapper;
    address tokenIn;
    uint160 priceSqrtX96Limit;
}

struct BuyParams {
    address tokenIn;
    SwapParams swap;
}

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
contract RushBuySell is UUPSUpgradeable, OwnableUpgradeable {
    ISwapUtil public swapUtil;

    uint8 public stage;

    error EndOfStrategy();

    event StrategyCompleted();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _swapUtil) external initializer {
        __Ownable_init();

        swapUtil = ISwapUtil(_swapUtil);

        stage = 0;
    }

    function takeAction(
        address _pool,
        BuyParams calldata _buyParams,
        SellParams calldata _sellParams
    ) external onlyOwner {
        if (stage == 0) {
            _performBuy(_pool, _buyParams.tokenIn, _buyParams.swap);
            stage = 1;
        } else if (stage == 1) {
            _performSell(_pool, !_buyParams.swap.zeroForOne, _sellParams);
            stage = 2;

            emit StrategyCompleted();
        } else {
            revert EndOfStrategy();
        }
    }

    function reset() external onlyOwner {
        stage = 0;
    }

    function withdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
    }

    // ==================== Internal Methods ====================

    function _performBuy(
        address _pool,
        address _tokenIn,
        SwapParams calldata _params
    ) internal {
        swapUtil.swap(_pool, _tokenIn, _params);
    }

    function _performSell(
        address _pool,
        bool _zeroForOne,
        SellParams calldata _params
    ) internal {
        SwapParams memory params = SwapParams({
            swapper: _params.swapper,
            zeroForOne: _zeroForOne,
            priceSqrtX96Limit: _params.priceSqrtX96Limit,
            amountOutMin: 0,
            amountIn: int256(IERC20(_params.tokenIn).balanceOf(address(this)))
        });

        swapUtil.swap(_pool, _params.tokenIn, params);
    }

    /**
     *  Used to control authorization of upgrade methods
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        newImplementation; // silence the warning
    }
}
