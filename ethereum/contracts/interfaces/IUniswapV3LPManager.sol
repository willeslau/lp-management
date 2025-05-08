// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct IncreaseLiquidityParams {
    uint8 a;
}

struct DecreaseLiquidityParams {
    uint8 a;
}

struct RebalanceClosePostionParams {
    uint8 a;
}

struct ClosePostionParams {
    uint8 a;
}

struct RebalanceParams {
    uint8 a;
}

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
interface IUniswapV3LpManagerUserOperations {
    function injectPricinple() external;

    function increaseLiquidity(
        IncreaseLiquidityParams calldata _params
    ) external;

    function decreaseLiquidity(
        DecreaseLiquidityParams calldata _params
    ) external;

    function batchCollectFees(uint32[] calldata _vaultIds) external;

    function closePosition(ClosePostionParams calldata _params) external;

    function closeVault(uint32 _vaultId) external;
}

interface IUniswapV3LpManagerRebalance {
    function rebalanceClosePosition(
        RebalanceClosePostionParams calldata _params
    ) external;

    function rebalance(RebalanceParams calldata _params) external;
}

interface IUniswapV3LpManagerEscape {
    function escapeHatchBurn(
        address _pool,
        uint128 _liqiudity,
        int24 tickLower,
        int24 tickUpper,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external;

    function escapeHatchCollect(
        address _pool,
        int24 tickLower,
        int24 tickUpper
    ) external;

    function shutdown(uint8 _tokenPairId) external;
}
