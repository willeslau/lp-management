import { Contract, Signer } from "ethers";
import { loadContract } from "../scripts/util";

export interface MintParams {
    tickLower: bigint,
    tickUpper: bigint,
    amount0Desired: bigint,
    amount1Desired: bigint,
    amount0Min: bigint,
    amount1Min: bigint,
}

export interface MintPosition {
    positionKey: string,
    amount0: bigint,
    amount1: bigint,
}

export class LPManagerTest {
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

    private parsePositionChangedLog(logs: any[]): PositionChanged {
        let amount0 = BigInt(0);
        let amount1 = BigInt(0);
        let positionKey = undefined;
        let change = PositionChange.Closed;

        logs.forEach((log: any) => {
            try {
              // Attempt to parse the log using the contract's interface
              const parsedLog = this.innerContract.interface.parseLog(log)!;
    
              if (parsedLog.name === "PositionChanged") {
                positionKey = parsedLog.args[0];
                amount0 = parsedLog.args[2];
                amount1 = parsedLog.args[3];

                const c = Number(parsedLog.args[1]);
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
            change,
            amount0,
            amount1,
            positionKey
        }
    }

    public async address(): Promise<string> {
        return await this.innerContract.getAddress();
    }
}

export enum PositionChange {
    Create,
    Increase,
    Descrese,
    Closed
}

export interface PositionChanged {
    positionKey: string,
    change: PositionChange,
    amount0: bigint,
    amount1: bigint
}
