// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Vault, VaultReserves} from "../libraries/LibVault.sol";
import {SwapParams} from "../SwapUtil.sol";

struct TokenPairAmount {
    uint256 amount0;
    uint256 amount1;
}

struct PositionInfo {
    int24 tickLower;
    int24 tickUpper;
    bool isActive;
}

struct MintParams {
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Min;
    uint256 amount1Min;
}

struct RebalanceParams {
    uint32 vaultId;
    SwapParams swap;
    MintParams mint;
}

struct OpenVaultParams {
    uint256 amount0;
    uint256 amount1;
}

struct VaultReserveChange {
    uint256 change0;
    uint256 change1;
    uint256 reserve0;
    uint256 reserve1;
}

struct CloseVaultPositionParams {
    uint32 vaultId;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Min;
    uint256 amount1Min;
    bool compoundFee;
}

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
interface IUniswapV3LpManagerV2 {
    event VaultClosed(uint64 indexed operationNonce, uint32 vaultId);
    event VaultCreated(
        uint64 indexed operationNonce,
        uint8 tokenPairId,
        uint32 vaultId,
        uint256 reserve0,
        uint256 reserve1
    );
    event VaultReserveIncreased(
        uint64 indexed operationNonce,
        uint32 vaultId,
        VaultReserveChange change
    );

    event FeesCollected(
        uint64 indexed operationNonce,
        uint32 vaultId,
        uint128 fee0,
        uint128 fee1,
        uint128 protocolFee0,
        uint128 protocolFee1
    );

    event TokensSent(bool isSentToPool, uint256 amount0, uint256 amount1);

    event VaultPositionOpened(
        uint64 indexed operationNonce,
        address liquidityOwner,
        uint32 vaultId,
        uint128 liquidity,
        int24 tickLower,
        int24 tickUpper,
        uint256 reserve0,
        uint256 reserve1
    );

    event VaultPositionClosed(
        uint64 indexed operationNonce,
        address liquidityOwner,
        uint32 vaultId,
        uint256 reserve0,
        uint256 reserve1
    );

    function getOperationNonce() external view returns (uint64);

    function listVaults(
        uint32[] calldata _vaultIds
    ) external view returns (uint64 nonce, Vault[] memory);

    function listActiveVaults(
        uint8 _tokenPairId
    ) external view returns (uint32[] memory);

    function openVaults(
        uint8 _tokenPairId,
        OpenVaultParams[] calldata _params
    ) external;

    /// @notice Inject principle into each vault specified. Does not who can restrict fund injection
    function injectPricinple(
        uint8 _tokenPairId,
        VaultReserves[] calldata _reserves
    ) external;

    /// @notice Close the vault from the liquidity owner
    function closeVault(uint32 _vaultId) external;

    function closeVaultPosition(
        CloseVaultPositionParams calldata _params
    ) external;

    function rebalance(RebalanceParams calldata _params) external;
}
