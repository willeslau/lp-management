import { Contract, ContractRunner, Signer, solidityPackedKeccak256, ZeroAddress } from "ethers";
import { loadContract, loadContractForQuery } from "./util";
import { TickLibrary } from '@uniswap/v3-sdk';
import JSBI from "jsbi";

const Q128 = 340282366920938463463374607431768211456n;

export interface SwapState {
    zeroForOne: boolean,


    tickLower: number,
    tickUpper: number,

    priceRatioLowerX96: bigint,
    priceRatioX96: bigint
    priceRatioUpperX96: bigint,

    priceLimitSqrtX96: bigint,
    priceLimitX96: bigint,

    amountIn: bigint,
    amountOut: bigint,

    rX96: bigint,
}

export interface BuyParams{
    pool: string,
    decimal0: number,
    decimal1: number,
    slippageProtectionSqrt: number,
    priceProtection: bigint,
    lowerBoundSqrt: number,
    upperBoundSqrt: number,
    token0: string,
    token1: string,
}

export class RushBuy {
    contract: Contract;
    readonly address: string;

    constructor(contract: Contract, address: string) {
        this.contract = contract;
        this.address = address;
    }

    public static async fromConfig(caller: Signer, rushBuy: string): Promise<RushBuy> {
        const lp = await loadContract("RushBuy", rushBuy, caller);
        return new RushBuy(lp, rushBuy);
    }

    public async RATIO_SQRT_BASE(): Promise<bigint> {
        return await this.contract.RATIO_SQRT_BASE();
    }

    public async buy(params: BuyParams): Promise<void> {
        const tx = await this.contract.buy(params);
        await tx.wait();
    }

    public async closePosition(): Promise<void> {
        const tx = await this.contract.closePosition();
        await tx.wait();
    }

    public async createBuyParams(
        pool: string,
        token0: string,
        token1: string,
        decimal0: number,
        decimal1: number,

        zeroForOne: boolean,
        maxSlippage: number,
        lowerBound: number,
        upperBound: number,
    ): Promise<BuyParams> {
        const base = await this.RATIO_SQRT_BASE();

        let slippageProtectionSqrt = 0;

        if (zeroForOne) {
            slippageProtectionSqrt = Math.sqrt(1 - maxSlippage);
        } else {
            slippageProtectionSqrt = Math.sqrt(1 + maxSlippage);
        }

        return {
            pool,
            decimal0,
            decimal1,
            slippageProtectionSqrt: Math.floor(slippageProtectionSqrt * Number(base)),
            lowerBoundSqrt: Math.floor(Math.sqrt(lowerBound) * Number(base)),
            upperBoundSqrt: Math.floor(Math.sqrt(upperBound) * Number(base)),
            token0,
            token1,
        };
    }

    public async calculateSwapState(params: BuyParams): Promise<SwapState> {
        const result = await this.contract.calculateSwapState(params);
        return {
            zeroForOne: result.zeroForOne,
            priceRatioX96: result.priceRatioX96,
            tickLower: result.tickLower,
            tickUpper: result.tickUpper,
            priceRatioLowerX96: result.priceRatioLowerX96,
            priceRatioUpperX96: result.priceRatioUpperX96,
            priceLimitSqrtX96: result.priceLimitSqrtX96,
            priceLimitX96: result.priceLimitX96,
            amountIn: result.amountIn,
            amountOut: result.amountOut,
            rX96: result.rX96,
        };
    }
}
