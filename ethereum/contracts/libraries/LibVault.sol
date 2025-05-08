// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct TokenPairAmount {
    uint256 amount0;
    uint256 amount1;
}

struct PositionInfo {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
}

struct Vault {
    uint8 tokenPairId;
    uint32 vaultId;
    TokenPairAmount feeEarned;
    TokenPairAmount reserves;
    PositionInfo position;
}

struct VaultReserves {
    uint32 vaultId;
    uint256 amount0;
    uint256 amount1;
}

struct VaultTracker {
    uint32 nextVaultId;
    mapping(uint8 => uint32[]) vaultIds;
    mapping(uint32 => Vault) vaults;
    mapping(int48 => bool) tickRangeLock;
}

library LibVault {
    error NoActivePosition(uint32 vaultId);

    int24 constant NO_TICK = type(int24).max;

    function getReserves(
        Vault storage vault
    ) internal view returns (uint256, uint256) {
        return (vault.reserves.amount0, vault.reserves.amount1);
    }

    function init(
        Vault storage vault,
        uint8 _tokenPairId,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        vault.tokenPairId = _tokenPairId;
        vault.reserves.amount0 = _amount0;
        vault.reserves.amount1 = _amount1;
    }

    function hasActivePosition(
        Vault storage vault
    ) internal view returns (bool) {
        return vault.position.liquidity != 0;
    }

    function getActivePosition(
        Vault storage vault
    ) internal view returns (PositionInfo memory pos) {
        pos = vault.position;
        if (pos.liquidity == 0) {
            revert NoActivePosition(vault.vaultId);
        }
    }

    function setReserves(
        Vault storage vault,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        vault.reserves.amount0 = _amount0;
        vault.reserves.amount1 = _amount1;
    }

    function increaseReserves(
        Vault storage vault,
        uint128 _amount0,
        uint128 _amount1
    ) internal returns (uint256 reserve0, uint256 reserve1) {
        reserve0 = vault.reserves.amount0;
        reserve1 = vault.reserves.amount1;

        reserve0 += _amount0;
        reserve1 += _amount1;

        vault.reserves.amount0 = reserve0;
        vault.reserves.amount1 = reserve1;
    }

    function increaseFees(
        Vault storage vault,
        uint128 _amount0,
        uint128 _amount1
    ) internal {
        vault.feeEarned.amount0 += _amount0;
        vault.feeEarned.amount1 += _amount1;
    }

    function clearPosition(Vault storage vault) internal {
        vault.position.liquidity = 0;
    }

    function setPosition(
        Vault storage vault,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 _liquidity
    ) internal {
        vault.position.tickUpper = _tickUpper;
        vault.position.tickLower = _tickLower;
        vault.position.liquidity = _liquidity;
    }
}

library LibVaultTracker {
    using LibVault for Vault;

    error VaultNotExists(uint32 vaultId);
    error TokenPairIdNotMatch(uint8 received, uint8 expected);

    function listVaults(
        VaultTracker storage self,
        uint32[] calldata _vaultIds
    ) internal view returns (Vault[] memory vaults) {
        vaults = new Vault[](_vaultIds.length);
        for (uint256 i = 0; i < _vaultIds.length; ) {
            vaults[i] = self.vaults[_vaultIds[i]];
            unchecked {
                i++;
            }
        }
    }

    function listActiveVaults(
        VaultTracker storage self,
        uint8 _tokenPairId
    ) internal view returns (uint32[] memory vaults) {
        uint256 total = self.vaultIds[_tokenPairId].length;
        vaults = new uint32[](total);

        for (uint256 i = 0; i < total; ) {
            vaults[i] = self.vaultIds[_tokenPairId][i];

            unchecked {
                i++;
            }
        }
    }

    function getVault(
        VaultTracker storage self,
        uint32 _vaultId
    ) internal view returns (Vault storage vault) {
        vault = self.vaults[_vaultId];

        if (vault.vaultId != _vaultId) revert VaultNotExists(_vaultId);
    }

    function createVault(
        VaultTracker storage self,
        uint8 _tokenPairId,
        uint256 _amount0,
        uint256 _amount1
    ) internal returns (uint32 vaultId) {
        vaultId = self.nextVaultId;
        self.nextVaultId = vaultId + 1;

        self.vaultIds[_tokenPairId].push(vaultId);

        Vault storage vault = self.vaults[vaultId];
        vault.vaultId = vaultId;
        vault.init(_tokenPairId, _amount0, _amount1);
    }

    function lockTickRange(
        VaultTracker storage self,
        int24 _tickLower,
        int24 _tickUpper
    ) internal {
        int48 lock = (_tickLower << 24) + _tickUpper;
        self.tickRangeLock[lock] = true;
    }

    function unlockTickRange(
        VaultTracker storage self,
        int24 _tickLower,
        int24 _tickUpper
    ) internal {
        int48 lock = (_tickLower << 24) + _tickUpper;
        delete self.tickRangeLock[lock];
    }

    function removeVault(
        VaultTracker storage self,
        uint8 _tokenPairId,
        uint32 _vault
    ) internal {
        uint256 total = self.vaultIds[_tokenPairId].length;
        for (uint256 i = 0; i < total; ) {
            uint32 v = self.vaultIds[_tokenPairId][i];
            if (v == _vault) {
                self.vaultIds[_tokenPairId][total - 1] = v;
                self.vaultIds[_tokenPairId].pop();
                return;
            }
            unchecked {
                i++;
            }
        }
    }

    function updateVaultReserves(
        VaultTracker storage self,
        uint8 _tokenPairId,
        VaultReserves calldata _params
    ) internal returns (uint256 reserve0, uint256 reserve1) {
        Vault storage vault = getVault(self, _params.vaultId);
        if (vault.tokenPairId != _tokenPairId) {
            revert TokenPairIdNotMatch(_tokenPairId, vault.tokenPairId);
        }

        reserve0 = vault.reserves.amount0;
        reserve1 = vault.reserves.amount1;

        reserve0 += _params.amount0;
        reserve1 += _params.amount1;

        vault.reserves.amount0 = reserve0;
        vault.reserves.amount1 = reserve1;
    }
}
