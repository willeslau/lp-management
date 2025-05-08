// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;


import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Vault, PositionInfo, VaultReserves, VaultTracker, LibVault, LibVaultTracker} from "../libraries/LibVault.sol";
import {UniswapV3LpManagerAdmin} from "./UniswapV3LpManagerAdmin.sol";
import {IUniswapV3LpManagerV2, VaultReserveChange, CloseVaultPositionParams, RebalanceParams, OpenVaultParams} from "./IUniswapV3LpManagerV2.sol";

import {IUniswapV3TokenPairs, TokenPair, TokenPairAdresses} from "../interfaces/IUniswapV3TokenPairs.sol";
import {LiquidityChangeOutput} from "../interfaces/IUniswapV3PoolProxy.sol";
import {UniswapV3PoolsUtil} from "../UniswapV3PoolsUtil.sol";
import {ISwapUtil, SwapParams} from "../SwapUtil.sol";

/// @title Uniswap V3 LP Manager
/// @notice Manages Uniswap V3 liquidity positions
contract UniswapV3LpManagerV2 is
    UUPSUpgradeable,
    UniswapV3PoolsUtil,
    UniswapV3LpManagerAdmin,
    IUniswapV3LpManagerV2
{
    uint128 constant UINT128_MAX = 340282366920938463463374607431768211455;

    using SafeERC20 for IERC20;
    using LibVault for Vault;
    using LibVaultTracker for VaultTracker;

    error CloseVaultPositionFirst(uint32 vaultId, PositionInfo position);
    error SwapAmountExceedReserve(int256 amountIn, uint256 reserve);
    error CloseVaultPositionOutdatedParams(uint32 vaultId, PositionInfo position);
    
    /// @notice Tracks all the vault currently active in the contract
    VaultTracker private vaultTracker;
    uint64 public operationNonce;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _supportedTokenPairs,
        address _swapUtil,
        address _liquidityOwner,
        address _balancer
    ) external initializer {
        __Ownable_init();

        supportedTokenPairs = IUniswapV3TokenPairs(_supportedTokenPairs);
        liquidityOwner = _liquidityOwner;
        balancer = _balancer;

        swapUtil = ISwapUtil(_swapUtil);
        protocolFeeRate = 50;

        operationNonce = 1;
    }

    function getOperationNonce() external view returns(uint64) {
        return operationNonce;
    }

    function listVaults(
        uint32[] calldata _vaultIds
    ) external view returns (uint64, Vault[] memory) {
        return (operationNonce, vaultTracker.listVaults(_vaultIds));
    }

    function listActiveVaults(
        uint8 _tokenPairId
    ) external view returns (uint32[] memory) {
        return vaultTracker.listActiveVaults(_tokenPairId);
    }

    function openVaults(
        uint8 _tokenPairId,
        OpenVaultParams[] calldata _params
    ) external {
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(
            _tokenPairId
        );

        (uint256 amount0, uint256 amount1) = (0, 0);
        uint64 nonce = operationNonce;

        uint256 total = _params.length;
        for (uint256 i = 0; i < total; ) {
            uint32 vaultId = vaultTracker.createVault(
                _tokenPairId,
                _params[i].amount0,
                _params[i].amount1
            );

            amount0 += _params[i].amount0;
            amount1 += _params[i].amount1;

            emit VaultCreated(
                nonce,
                _tokenPairId,
                vaultId,
                _params[i].amount0,
                _params[i].amount1
            );

            unchecked {
                i++;
                nonce += 1;
            }
        }

        _transferIn(tokenPair, amount0, amount1);
        operationNonce = nonce;
    }

    /// @notice Inject principle into each vault specified. Does not who can restrict fund injection
    function injectPricinple(
        uint8 _tokenPairId,
        VaultReserves[] calldata _reserves
    ) external {
        TokenPair memory tokenPair = supportedTokenPairs.getTokenPair(
            _tokenPairId
        );

        (uint256 amount0, uint256 amount1) = (0, 0);
        uint64 nonce = operationNonce;

        for (uint256 i = 0; i < _reserves.length; ) {
            (uint256 reserve0, uint256 reserve1) = vaultTracker
                .updateVaultReserves(_tokenPairId, _reserves[i]);

            amount0 += _reserves[i].amount0;
            amount1 += _reserves[i].amount1;

            emit VaultReserveIncreased(
                nonce,
                _reserves[i].vaultId,
                VaultReserveChange({
                    change0: _reserves[i].amount0,
                    change1: _reserves[i].amount1,
                    reserve0: reserve0,
                    reserve1: reserve1
                })
            );

            unchecked {
                i++;
                nonce++;
            }
        }

        _transferIn(tokenPair, amount0, amount1);
        operationNonce = nonce;
    }

    /// @notice Close the vault from the liquidity owner
    function closeVault(uint32 _vaultId) external onlyAddress(liquidityOwner) {
        Vault storage vault = vaultTracker.getVault(_vaultId);

        if (vault.hasActivePosition()) revert CloseVaultPositionFirst(_vaultId, vault.getActivePosition());

        vaultTracker.removeVault(vault.tokenPairId, _vaultId);

        TokenPairAdresses memory t = supportedTokenPairs.getTokenPairAddress(
            vault.tokenPairId
        );
        IERC20(t.token0).safeTransfer(msg.sender, vault.reserves.amount0);
        IERC20(t.token1).safeTransfer(msg.sender, vault.reserves.amount1);

        uint64 nonce = operationNonce;
        emit VaultClosed(nonce, _vaultId);

        operationNonce = nonce + 1;
    }

    function closeVaultPosition(
        CloseVaultPositionParams calldata _params
    ) external onlyAddress(balancer) {
        Vault storage vault = vaultTracker.getVault(_params.vaultId);

        PositionInfo memory position = vault.getActivePosition();
        if (position.tickLower != _params.tickLower && position.tickUpper != _params.tickUpper) {
            revert CloseVaultPositionOutdatedParams(_params.vaultId, position);
        }

        IUniswapV3Pool pool = IUniswapV3Pool(
            supportedTokenPairs.getTokenPairPool(vault.tokenPairId)
        );
        uint64 nonce = operationNonce;

        (uint128 fee0, uint128 fee1) = _prepareFeeForCollection(
            nonce,
            _params.vaultId,
            vault,
            pool,
            position,
            _params.compoundFee
        );

        uint128 liquidity = _positionLiquidity(pool, position);
        _burnWithSlippageCheck(
            pool,
            liquidity,
            position,
            _params.amount0Min,
            _params.amount1Min
        );

        (uint128 amount0Collected, uint128 amount1Collected) = _collect(
            pool,
            address(this),
            position,
            UINT128_MAX,
            UINT128_MAX
        );

        amount0Collected -= fee0;
        amount1Collected -= fee1;

        vaultTracker.unlockTickRange(position.tickLower, position.tickUpper);
        vault.clearPosition();

        (uint256 reserve0, uint256 reserve1) = vault.increaseReserves(amount0Collected, amount1Collected);

        emit TokensSent(
            false,
            amount0Collected,
            amount1Collected
        );

        nonce += 1;
        emit VaultPositionClosed(
            nonce,
            liquidityOwner,
            _params.vaultId,
            reserve0,
            reserve1
        );

        operationNonce = nonce + 1;
    }

    function rebalance(
        RebalanceParams calldata _params
    ) external onlyAddress(balancer) {
        Vault storage vault = vaultTracker.getVault(_params.vaultId);

        // split close and rebalance in two txns for gas
        if (vault.hasActivePosition())
            revert CloseVaultPositionFirst(_params.vaultId, vault.getActivePosition());

        TokenPairAdresses memory tokenPair = supportedTokenPairs
            .getTokenPairAddress(vault.tokenPairId);

        uint256 reserve0;
        uint256 reserve1;
        {
            (reserve0, reserve1) = vault.getReserves();
            _ensureCanSwap(reserve0, reserve1, _params.swap);

            (int256 amount0Delta, int256 amount1Delta) = _swap(
                _params.swap,
                tokenPair
            );

            reserve0 = _add(reserve0, amount0Delta);
            reserve1 = _add(reserve1, amount1Delta);
        }

        vaultTracker.lockTickRange(
            _params.mint.tickLower,
            _params.mint.tickUpper
        );

        LiquidityChangeOutput memory output = _addLiquidity(
            tokenPair,
            _params.mint.tickLower,
            _params.mint.tickUpper,
            reserve0,
            reserve1
        );

        reserve0 -= output.amount0;
        reserve1 -= output.amount1;

        vault.setPosition(_params.mint.tickLower, _params.mint.tickUpper, output.liquidity);
        vault.setReserves(reserve0, reserve1);

        uint64 nonce = operationNonce;

        emit TokensSent(
            true,
            output.amount0,
            output.amount1
        );
        emit VaultPositionOpened(
            nonce,
            liquidityOwner,
            _params.vaultId,
            output.liquidity,
            _params.mint.tickLower,
            _params.mint.tickUpper,
            reserve0,
            reserve1
        );

        operationNonce = nonce + 1;
    }

    function withdraw(address _token) external onlyOwner() {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, balance);
    }

    /**
     *  Used to control authorization of upgrade methods
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal view override onlyOwner {
        newImplementation; // silence the warning
    }

    // ==================== Internal Methods ====================

    function _prepareFeeForCollection(
        uint64  _operationNonce,
        uint32 _vaultId,
        Vault storage _vault,
        IUniswapV3Pool _pool,
        PositionInfo memory _position,
        bool _compoundFee
    ) internal returns (uint128 fee0, uint128 fee1) {
        _pool.burn(_position.tickLower, _position.tickUpper, 0);

        (fee0, fee1) = _tokensOwned(_pool, _position);
        (uint128 protocolFee0, uint128 protocolFee1) = (
            _calculateProtocolFee(fee0),
            _calculateProtocolFee(fee1)
        );

        // send protocol fee to contract owner
        if (protocolFee0 != 0 || protocolFee1 != 0) {
            _collect(_pool, owner(), _position, protocolFee0, protocolFee1);

            fee0 -= protocolFee0;
            fee1 -= protocolFee1;
        }

        emit FeesCollected(_operationNonce, _vaultId, fee0, fee1, protocolFee0, protocolFee1);

        _vault.increaseFees(fee0, fee1);

        if (!_compoundFee) {
            _collect(_pool, liquidityOwner, _position, fee0, fee1);
            fee0 = 0;
            fee1 = 0;
        }
    }

    function _add(uint256 _num, int256 _val) internal pure returns (uint256) {
        if (_val >= 0) {
            return _num + uint256(_val);
        }
        return _num - uint256(-_val);
    }

    function _ensureCanSwap(
        uint256 _reserve0,
        uint256 _reserve1,
        SwapParams calldata _params
    ) internal pure {
        // sanitity check
        require(_params.amountIn > 0, "sc");

        if (_params.zeroForOne) {
            if (_reserve0 < uint256(_params.amountIn)) {
                revert SwapAmountExceedReserve(_params.amountIn, _reserve0);
            }
            return;
        }

        if (!_params.zeroForOne) {
            if (_reserve1 < uint256(_params.amountIn)) {
                revert SwapAmountExceedReserve(_params.amountIn, _reserve1);
            }
        }
    }

    function _swap(
        SwapParams calldata _params,
        TokenPairAdresses memory _tokenPair
    ) internal returns (int256 amount0, int256 amount1) {
        if (_params.zeroForOne) {
            IERC20(_tokenPair.token0).approve(
                address(swapUtil),
                uint256(_params.amountIn)
            );
            return swapUtil.swap(_tokenPair.pool, _tokenPair.token0, _params);
        }

        IERC20(_tokenPair.token1).approve(
            address(swapUtil),
            uint256(_params.amountIn)
        );
        return swapUtil.swap(_tokenPair.pool, _tokenPair.token1, _params);
    }

    /// @dev Transfers user funds into this contract and approves uniswap for spending it
    function _transferIn(
        TokenPair memory _tokenPair,
        uint256 _amount0,
        uint256 _amount1
    ) internal {
        if (_amount0 != 0) {
            IERC20(_tokenPair.token0).safeTransferFrom(
                msg.sender,
                address(this),
                _amount0
            );
        }
        if (_amount1 != 0) {
            IERC20(_tokenPair.token1).safeTransferFrom(
                msg.sender,
                address(this),
                _amount1
            );
        }
    }
}
