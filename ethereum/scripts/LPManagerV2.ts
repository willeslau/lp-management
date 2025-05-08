import { Contract, ContractRunner, Signer, solidityPackedKeccak256, ZeroAddress } from "ethers";
import { loadContract, loadContractForQuery } from "./util";
import { TickLibrary } from '@uniswap/v3-sdk';
import JSBI from "jsbi";

const Q128 = 340282366920938463463374607431768211456n;

export enum PositionChange {
    Create = 1,
    Closed,
}

export type VaultPositionChangedEvent = {
  liquidityOwner: string;
  vaultId: number;
  change: PositionChange;
  amount0: bigint;
  amount1: bigint;
};

  
// Swapper Enum
export enum Swapper {
    UniswapPool = 0, // Enum values in Solidity are 0-based
  }
  
  // SwapParams Struct
  export type SwapParams = {
    swapper: Swapper;
    zeroForOne: boolean;
    priceSqrtX96Limit: bigint; // uint160
    amountOutMin: bigint;      // int256
    amountIn: bigint;          // int256
  };

  // MintParams Struct
  export type MintParams = {
    tickLower: number;  // int24
    tickUpper: number;  // int24
    amount0Min: bigint; // uint256
    amount1Min: bigint; // uint256
  };
  
  // RebalanceParams Struct
  export type RebalanceParams = {
    vaultId: number;       // uint32
    swap: SwapParams;
    mint: MintParams;
  };
  
// OpenVaultParams Struct
export type OpenVaultParams = {
    amount0: bigint;   // uint256
    amount1: bigint;   // uint256
  };
  
export interface TokenPair {
    id: bigint,
    pool: string,
    token0: string,
    token1: string,
    poolFee: bigint,
}

export interface TokenAmounts {
    amount0: bigint,
    amount1: bigint
}

export interface VaultReserves {
    vaultId: number,
    amount0: bigint,
    amount1: bigint,
}

export interface CloseVaultPosition {
    vaultId: number,
    tickLower: number,
    tickUpper: number,
    amount0Min: bigint,
    amount1Min: bigint,
    compoundFee: boolean,
}

export class LPManagerV2 {
    contract: Contract;
    uniswapUtil: Contract;

    constructor(contract: Contract, uniswapUtil: Contract) {
        this.contract = contract;
        this.uniswapUtil = uniswapUtil;
    }

    public static async fromConfig(caller: Signer, lpManager: string, uniswapUtil: string): Promise<LPManagerV2> {
        const lp = await loadContract("UniswapV3LpManagerV2", lpManager, caller);
        const ut = await loadContract("UniswapUtil", uniswapUtil, caller);
        return new LPManagerV2(lp, ut);
    }

    public async injectPricinple(tokenPairId: number, params: VaultReserves[]): Promise<void> {
        const tokenPair = await this.getTokenPair(tokenPairId);

        let amount0 = BigInt(0);
        let amount1 = BigInt(0);

        for (const p of params) {
            amount0 += p.amount0;
            amount1 += p.amount1;
        }

        console.log(tokenPair);

        await this.increaseAllowanceIfNeeded(tokenPair.token0, amount0);
        await this.increaseAllowanceIfNeeded(tokenPair.token1, amount1);

        await this.contract.injectPricinple(tokenPairId, params);
        return;
    }

    public async openVaults(tokenPairId: number, params: OpenVaultParams[]): Promise<void> {
        const tokenPair = await this.getTokenPair(tokenPairId);
        
        let amount0 = BigInt(0);
        let amount1 = BigInt(0);
        for (const p of params) {
            amount0 += p.amount0;
            amount1 += p.amount1;
        }

        await this.increaseAllowanceIfNeeded(tokenPair.token0, amount0);
        await this.increaseAllowanceIfNeeded(tokenPair.token1, amount1);

        await this.contract.openVaults(tokenPairId, params);
    }

    public async listActiveVaults(tokenPairId: number): Promise<number[]> {
        const result: bigint[] = await this.contract.listActiveVaults(tokenPairId);
        return result.map(v => Number(v)); // Convert BigInts to JS numbers
    }

    public async listVaults(vaultIds: number[]): Promise<any> {
        return await this.contract.listVaults(vaultIds);
    }

    public async closeVault(vaultId: number): Promise<void> {
        await this.contract.closeVault(vaultId);
    }

    public async rebalance(params: RebalanceParams): Promise<VaultPositionChangedEvent> {
        const tx = await this.contract.rebalance(params);
        const receipt = await tx.wait();
        return this.parsePositionChangedLog(receipt.logs)!;
    }

    public async closeVaultPosition(params: CloseVaultPosition): Promise<VaultPositionChangedEvent> {
        const tx = await this.contract.closeVaultPosition(params);
        const receipt = await tx.wait();

        return this.parsePositionChangedLog(receipt.logs)!;
    }

    public useCaller(caller: Signer) {
        // @ts-ignore
        this.contract = this.contract.connect(caller);
    }

    public async decimals(tokenPairId: number): Promise<number[]> {
        const tokenPair = await this.getTokenPair(tokenPairId);

        const caller = this.contract.runner! as Signer;
        const token0 = await loadContract("ERC20", tokenPair.token0, caller);
        const token1 = await loadContract("ERC20", tokenPair.token1, caller);
        
        return [await token0.decimals(), await token1.decimals()];
    }

    public async names(tokenPairId: number): Promise<string[]> {
        const tokenPair = await this.getTokenPair(tokenPairId);

        const caller = this.contract.runner! as Signer;
        const token0 = await loadContract("ERC20", tokenPair.token0, caller);
        const token1 = await loadContract("ERC20", tokenPair.token1, caller);
        
        return [await token0.name(), await token1.name()];
    }

    public async increaseAllowanceIfNeeded(token: string, amount: bigint): Promise<void> {
        const caller = this.contract.runner! as Signer;
        const spender = await this.contract.getAddress();

        const tokenContract = await loadContract("IERC20", token, caller);
        const currentAllowance = await tokenContract.allowance(await caller.getAddress(), spender);

        console.log(token, currentAllowance, amount, (await caller.getAddress()), spender);
        if (currentAllowance >= amount) {
            return;
        }

        const tx = await tokenContract.approve(spender, amount);
        await tx.wait();
    }

    public async withdraw(token: string): Promise<void> {
        await this.contract.withdraw(token);
    }

    private parsePositionChangedLog(logs: any[]): VaultPositionChangedEvent | null {
        for (const log of logs) {
            try {
              const parsed = this.contract.interface.parseLog(log)!;
              if (parsed.name === "VaultPositionChanged") {
                const { liquidityOwner, vaultId, change, amount0, amount1 } = parsed.args;
        
                return {
                  liquidityOwner,
                  vaultId: Number(vaultId),
                  change: change as PositionChange,
                  amount0: BigInt(amount0.toString()),
                  amount1: BigInt(amount1.toString()),
                };
              }
            } catch {
              // Skip logs that don't match the interface
            }
        }
        
        return null; // No matching event found
    }

    public async address(): Promise<string> {
        return await this.contract.getAddress();
    }

    public runner(): ContractRunner {
        return this.contract.runner!;
    }

    public async getTokenPair(tokenPairId: number): Promise<TokenPair> {
        const tokenPairAddress = await this.contract.supportedTokenPairs();
        const tokenPairContract = await loadContractForQuery("IUniswapV3TokenPairs", tokenPairAddress, this.contract.runner!);
        return await tokenPairContract.getTokenPair(tokenPairId);
    }

    public async getReservesWithEarnings(tokenPairId: number): Promise<{ fee: TokenAmounts, reserves: TokenAmounts}> {
        const fees = await this.contract.getFeesEarned(tokenPairId);
        const reserves = await this.contract.getReserveAmounts(tokenPairId);
        return {
            fee: {
                amount0: fees[0],
                amount1: fees[1],
            },
            reserves: {
                amount0: reserves[0],
                amount1: reserves[1]
            }
        }
    }

    public async getPositionFees(positionKey: string): Promise<[bigint, bigint]> {
        const positionInfo = await this.getPosition(positionKey);
        const tokenPair = await this.getTokenPair(positionInfo.tokenPairId);

        const uniswapContract = await loadContractForQuery('IUniswapV3Pool', tokenPair.pool, this.contract.runner!);
        const slot = await uniswapContract.slot0();

        const tickLower = positionInfo.tickLower;
        const tickCurrent = slot.tick;
        const tickUpper = positionInfo.tickUpper;

        const tickLowerInfo = await uniswapContract.ticks(tickLower);
        const tickUpperInfo = await uniswapContract.ticks(tickUpper);

        const [fee0Rate, fee1Rate] = TickLibrary.getFeeGrowthInside(
            {
                feeGrowthOutside0X128: JSBI.BigInt(tickLowerInfo.feeGrowthOutside0X128.toString()),
                feeGrowthOutside1X128: JSBI.BigInt(tickLowerInfo.feeGrowthOutside1X128.toString())
            },
            {
                feeGrowthOutside0X128: JSBI.BigInt(tickUpperInfo.feeGrowthOutside0X128.toString()),
                feeGrowthOutside1X128: JSBI.BigInt(tickUpperInfo.feeGrowthOutside1X128.toString())
            },
            Number(tickLower),
            Number(tickUpper),
            Number(tickCurrent),
            JSBI.BigInt((await uniswapContract.feeGrowthGlobal0X128()).toString()),
            JSBI.BigInt((await uniswapContract.feeGrowthGlobal1X128()).toString()),
        );

        const uniswapPositioKey = await this.getUniswapPositionKey(positionInfo.tickLower, positionInfo.tickUpper);
        const uniswapPosition = await uniswapContract.positions(uniswapPositioKey);

        const fee0 = this.calculateFee(BigInt(fee0Rate.toString()), BigInt(uniswapPosition.feeGrowthInside0LastX128), uniswapPosition.liquidity);
        const fee1 = this.calculateFee(BigInt(fee1Rate.toString()), BigInt(uniswapPosition.feeGrowthInside1LastX128), uniswapPosition.liquidity);

        return [fee0, fee1];
    }

    calculateFee(feeGrowthInsideNow: bigint, feeGrowthInsideBefore: bigint, liquidity: bigint): bigint {
        return (feeGrowthInsideNow - feeGrowthInsideBefore) * liquidity / Q128;
    }

    async getUniswapPositionKey(tickLower: bigint, tickUpper: bigint): Promise<string> {
        const owner = await this.contract.getAddress();
        return solidityPackedKeccak256(['address', 'int24', 'int24'], [owner, tickLower, tickUpper]);
    }
}
