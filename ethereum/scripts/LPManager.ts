import { Contract, Signer, ZeroAddress } from "ethers";
import { loadContract } from "./util";

export interface RebalanceParams {
    tokenPairId: number,
    sqrtPriceLimitX96: bigint,
    maxMintSlippageRate: number,
    tickLower: bigint,
    tickUpper: bigint,
    amount0: bigint,
    amount1: bigint,
    searchRange: SearchRange
}

export interface IncreasLiquidityParams {
    amount0: bigint,
    amount1: bigint,
    slippage: number,
}

export interface DecreasLiquidityParams {
    newLiquidity: bigint,
    amount0: bigint,
    amount1: bigint,
}

export interface SearchRange {
    swapInLow: bigint,
    swapInHigh: bigint
    searchLoopNum: number,
}

export interface RebalanceClosePosition {
    amount0Min: bigint,
    amount1Min: bigint,
    compoundFee: boolean
}

export interface MintParams {
    tickLower: bigint,
    tickUpper: bigint,
    amount0Desired: bigint,
    amount1Desired: bigint,
    amount0Min: bigint,
    amount1Min: bigint,
}

export interface LpPosition {
    tokenPairId: number,
    tickLower: bigint,
    tickUpper: bigint,
    liquidity: bigint,
    amount0: bigint,
    amount1: bigint,
    fee0: bigint,
    fee1: bigint
}

export interface MintPosition {
    positionKey: string,
    amount0: bigint,
    amount1: bigint,
}

export interface ListPositionKeys {
    totalPositions: number,
    positionKeys: string[],
}

export class LPManager {
    innerContract: Contract;

    constructor(contract: Contract) {
        this.innerContract = contract;
    }

    private rateDeducted(amount: bigint, rate: number): bigint {
        return amount * BigInt(Math.floor(10000000 * (1 - rate))) / BigInt(10000000);
    }

    public useCaller(caller: Signer) {
        // @ts-ignore
        this.innerContract = this.innerContract.connect(caller);
    }

    public async getPosition(positionKey: string): Promise<LpPosition> {
        const pos = await this.innerContract.position(positionKey);
        return {
            liquidity: pos.liquidity,
            tokenPairId: pos.tokenPairId,
            amount0: pos.amount0,
            amount1: pos.amount1,
            fee0: pos.fee0,
            fee1: pos.fee1,
            tickLower: pos.tickLower,
            tickUpper: pos.tickUpper,
        }
    }

    public createMintParams(
        tickLower: bigint,
        tickUpper: bigint,
        amount0Desired: bigint,
        amount1Desired: bigint,
        slippage: number,
    ): MintParams {
        if (slippage >= 1) {
            throw Error("invalid slippage");
        }

        return {
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min: this.rateDeducted(amount0Desired, slippage),
            amount1Min: this.rateDeducted(amount1Desired, slippage),
        }
    }

    public toOnChainRate(num: number): number {
        return num * 1000;
    }

    public async listPositionKeys(startIndex: number, endIndex: number): Promise<ListPositionKeys> {
        const [total, pos] = await this.innerContract.listPositionKeys(startIndex, endIndex);
        return {
            totalPositions: total,
            positionKeys: pos
        };
    }

    public async increaseLiquidity(positionKey: string, params: IncreasLiquidityParams): Promise<PositionChanged> {
        const amount0Min = this.rateDeducted(params.amount0 as bigint, params.slippage);
        const amount1Min = this.rateDeducted(params.amount1 as bigint, params.slippage);
        const tx = await this.innerContract.increaseLiquidity(positionKey, params.amount0, params.amount1, amount0Min, amount1Min);
        const receipt = await tx.wait();
        return this.parsePositionChangedLog(receipt.logs);
    }

    public async decreaseLiquidity(positionKey: string, params: DecreasLiquidityParams): Promise<PositionChanged> {
        const tx = await this.innerContract.decreaseLiquidity(positionKey, params.newLiquidity, params.amount0, params.amount1);
        const receipt = await tx.wait();
        return this.parsePositionChangedLog(receipt.logs);
    }

    public async rebalance1For0(params: RebalanceParams): Promise<PositionChanged> {
        const tx = await this.innerContract.rebalance1For0(params);
        const receipt = await tx.wait();
        return this.parsePositionChangedLog(receipt.logs);
    }

    public async rebalance0For1(params: RebalanceParams): Promise<PositionChanged> {
        const tx = await this.innerContract.rebalance0For1(params);
        const receipt = await tx.wait();
        return this.parsePositionChangedLog(receipt.logs);
    }

    public async rebalanceClosePosition(
        positionKey: string,
        params: RebalanceClosePosition,
    ): Promise<PositionChanged> {
        const tx = await this.innerContract.rebalanceClosePosition(positionKey, params.amount0Min, params.amount1Min, params.compoundFee);
        const receipt = await tx.wait();

        return this.parsePositionChangedLog(receipt.logs);
    }

    public async mintNewPosition(tokenPairId: number, mintParams: MintParams): Promise<PositionChanged> {
        const tx = await this.innerContract.mint(tokenPairId, mintParams);
        const receipt = await tx.wait();

        return this.parsePositionChangedLog(receipt.logs);
    }

    public async increaseAllowanceIfNeeded(token: string, amount: bigint): Promise<void> {
        const caller = this.innerContract.runner! as Signer;
        const spender = await this.innerContract.getAddress();

        const tokenContract = await loadContract("IERC20", token, caller);
        const currentAllowance = await tokenContract.allowance(await caller.getAddress(), spender);

        if (currentAllowance >= amount) {
            return;
        }

        const tx = await tokenContract.approve(spender, amount);
        await tx.wait();
    }

    public async decodeLpSwapError(error: string): Promise<void> {
        const c = await loadContract("LiquiditySwapV3", ZeroAddress, this.innerContract.runner as Signer);

        let err;
        if (error.startsWith("0x")) {
            err = c.interface.getError(error.substring(2, 10));
        } else {
            err = c.interface.getError(error.substring(0, 8));
        }
        console.log(err);
        // c.interface.decodeErrorResult()
    }

    private parsePositionChangedLog(logs: any[]): PositionChanged {
        let amount0 = BigInt(0);
        let amount1 = BigInt(0);
        let positionKey = undefined;
        let change = PositionChange.Closed;
        let tokenPair = 0;

        logs.forEach((log: any) => {
            try {
              // Attempt to parse the log using the contract's interface
              const parsedLog = this.innerContract.interface.parseLog(log)!;
    
              if (parsedLog.name === "PositionChanged") {
                tokenPair = parsedLog.args[0];
                positionKey = parsedLog.args[1];
                amount0 = parsedLog.args[3];
                amount1 = parsedLog.args[4];

                const c = Number(parsedLog.args[2]);
                if (c === 0) {
                    change = PositionChange.Create;
                } else if (c === 1) {
                    change = PositionChange.Increase;
                } else if (c === 2) {
                    change = PositionChange.Descrese;
                } else if (c === 3) {
                    change = PositionChange.Closed;
                } else {
                    throw Error("invalid position");
                }

              } else {
                return;
              }
    
            } catch (error) {
              // The log might not belong to this contract, so skip it
            }
        });

        if (positionKey === undefined) {
            throw Error("mint transaction no position key found, report bug");
        }

        return {
            tokenPair,
            change,
            amount0,
            amount1,
            positionKey
        }
    }

    public async withdrawRemainingFunds(tokenPairId: number): Promise<void> {
        const tx = await this.innerContract.withdraw(tokenPairId);
        await tx.wait();
    }

    async closePosition(
        positionKey: string, 
        amount0Min: bigint = BigInt(0), 
        amount1Min: bigint = BigInt(0)
    ): Promise<PositionChanged> {
        const tx = await this.innerContract.closePosition(positionKey, amount0Min, amount1Min);
        const receipt = await tx.wait();
        return this.parsePositionChangedLog(receipt.logs);
    }
}

export enum PositionChange {
    Create,
    Increase,
    Descrese,
    Closed
}

export interface PositionChanged {
    tokenPair: number,
    positionKey: string,
    change: PositionChange,
    amount0: bigint,
    amount1: bigint
}