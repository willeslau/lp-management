// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {PositionInfo} from "./libraries/LibVault.sol";

error TokenAddressesNotSorted();
error PairAlreadyExists();
error InvalidPoolAddress();
error InvalidTokenAddress();
error TokenPairNotExits(uint8 id);

error SwapSlippageError(int256 incoming, int256 min);

error BurnSlippageError();
error UniswapCallFailed(string marker, bytes reason);

error CloseVaultPositionFirst(uint32 vaultId, PositionInfo position);
error SwapAmountExceedReserve(int256 amountIn, uint256 reserve);
error CloseVaultPositionOutdatedParams(uint32 vaultId, PositionInfo position);
