import { assert, Contract, ContractRunner, Provider, Signer, solidityPackedKeccak256 } from "ethers";
import { loadContract, loadContractForQuery } from "./util";
import { Pool, Position, TickLibrary, FullMath, maxLiquidityForAmounts, TickMath, SqrtPriceMath } from '@uniswap/v3-sdk';
import JSBI from "jsbi";
import { CurrencyAmount, Token } from "@uniswap/sdk-core";

const Q128 = 340282366920938463463374607431768211456n;

const Q96 = 79228162514264337593543950336n;
const Q96_JSBI = JSBI.BigInt(Q96.toString());

const SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

export interface TokenAmount {
    token0: number;
    token1: number;
}

export interface TickWithAmounts {
    tick: number;
    token0: number;
    token1: number;
}

export interface Loss {
    tick: number;
    token0: number;
    token1: number;
    impermanent: number;
    actual: number;
}


export interface Monitor {
    tickCurrent: bigint,
    fees: [bigint, bigint],
    principle: TokenAmount,
}

export class UniswapV3PoolUtil {
    contract: Contract;
    token0: Token;
    token1: Token;
    feeTier: number;

    constructor(
        contract: Contract,
        token0: Token,
        token1: Token,
        feeTier: number,
    ) {
        this.contract = contract;
        this.token0 = token0;
        this.token1 = token1;
        this.feeTier = feeTier;
    }

    public static async fromPool(chainId: number, pool: string, provider: Provider): Promise<UniswapV3PoolUtil> {
        const contract = await loadContractForQuery('IUniswapV3Pool', pool, provider);

        const token0Address = await contract.token0();
        const token1Address = await contract.token1();

        const [token1Name, token1Decimals] = await UniswapV3PoolUtil.tokenMetadata(token1Address, provider);
        const [token0Name, token0Decimals] = await UniswapV3PoolUtil.tokenMetadata(token1Address, provider);

        const token0 = new Token(chainId, token0Address, token0Decimals, token0Name, token0Name);
        const token1 = new Token(chainId, token1Address, token1Decimals, token1Name, token1Name);

        const feeTier = Number(await contract.fee());

        return new UniswapV3PoolUtil(contract, token0, token1, feeTier);
    }

    public async getPositionFees(owner: string, tickLower: number, tickUpper: number): Promise<Monitor> {
        const slot = await this.contract.slot0();

        const tickCurrent = slot.tick;

        const tickLowerInfo = await this.contract.ticks(tickLower);
        const tickUpperInfo = await this.contract.ticks(tickUpper);

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
            JSBI.BigInt((await this.contract.feeGrowthGlobal0X128()).toString()),
            JSBI.BigInt((await this.contract.feeGrowthGlobal1X128()).toString()),
        );

        const uniswapPositioKey = this.getUniswapPositionKey(owner, tickLower, tickUpper);
        const uniswapPosition = await this.contract.positions(uniswapPositioKey);

        const fee0 = this.calculateFee(BigInt(fee0Rate.toString()), BigInt(uniswapPosition.feeGrowthInside0LastX128), uniswapPosition.liquidity);
        const fee1 = this.calculateFee(BigInt(fee1Rate.toString()), BigInt(uniswapPosition.feeGrowthInside1LastX128), uniswapPosition.liquidity);

        const sqrtPriceX96 = slot.sqrtPriceX96;
        const inRangeLiquidity = await this.contract.liquidity();
        const liquidity = uniswapPosition.liquidity;

        if (liquidity !== BigInt(0)) {
            const uniswapP = new Position({
                pool: new Pool(this.token0, this.token1, this.feeTier, JSBI.BigInt(sqrtPriceX96.toString()), JSBI.BigInt(inRangeLiquidity.toString()), Number(tickCurrent)),
                liquidity: JSBI.BigInt(liquidity.toString()),
                tickLower: Number(tickLower),
                tickUpper: Number(tickUpper),
            });
            return {
                tickCurrent,
                fees: [fee0, fee1],
                principle: {
                    token0: Number(uniswapP.amount0.toExact()),
                    token1: Number(uniswapP.amount1.toExact()),
                }
            }
        } else {
            const principle = {
                token0: Number(await this.tokenBalance(this.token0.address)),
                token1: Number(await this.tokenBalance(this.token1.address)),
            }
            return {
                tickCurrent,
                fees: [BigInt(0), BigInt(0)],
                principle,
            }
        }
    }

    public balances(
        amount0: JSBI,
        amount1: JSBI,
        openPositionTick: number,
        tickLower: number,
        tickUpper: number,
    ): TickWithAmounts[] {
        const inRangeLiquidity = 0; // should not matter this calculating the position amounts

        const liquidity = maxLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(openPositionTick),
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0.toString(),
            amount1.toString(),
            true
        );

        const results = [];
        
        for (let tick = tickLower; tick <= tickUpper; tick += 1) {
            const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tick), inRangeLiquidity, tick);
            const position = new Position({ pool, liquidity, tickLower, tickUpper });
            const token0 = Number(position.amount0.toExact());
            const token1 = Number(position.amount1.toExact());

            results.push({
                tick,
                token0,
                token1,
            });
        }
    
        return results;
    }

    public singleSideToken1Losses(
        amount1: JSBI,
        tickLower: number,
        tickUpper: number,
        totalSwapLoss: number,
    ): Loss[] {
        const inRangeLiquidity = 0; // should not matter this calculating the position amounts

        const liquidity = maxLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(tickUpper),
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            0,
            amount1,
            true
        );

        if (JSBI.lessThanOrEqual(liquidity, JSBI.BigInt(0))) {
            throw Error("should not be 0 liquidity");
        }

        const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tickUpper), inRangeLiquidity, tickUpper);
        const amount1Start = Number(new Position({ pool, liquidity, tickLower, tickUpper }).amount1.toExact());

        const results = [];
        
        for (let tick = tickLower; tick <= tickUpper; tick += 1) {
            const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tick), inRangeLiquidity, tick);

            const position = new Position({ pool, liquidity, tickLower, tickUpper });
            const token0 = Number(position.amount0.toExact());
            const token1 = Number(position.amount1.toExact());

            const lossToken1 = (amount1Start - token1) - token0 / ((1 + totalSwapLoss) * Number(pool.token1Price.toSignificant(6)));
            const lossToken0 = lossToken1 * Number(pool.token1Price.toSignificant(6));
            results.push({
                tick,
                token0,
                token1,
                price0: pool.token0Price.toSignificant(5),
                price1: pool.token1Price.toSignificant(6),
                deltaToken1: amount1Start - token1,
                lossToken1,
                lossToken0,
            });
        }

        return results;
    }

    public singleSideToken0Losses(
        amount: JSBI,
        tickLower: number,
        tickUpper: number,
        totalSwapLoss: number,
    ): Loss[] {
        const inRangeLiquidity = 0; // should not matter this calculating the position amounts

        const liquidity = maxLiquidityForAmounts(
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount,
            0,
            true
        );

        if (JSBI.lessThanOrEqual(liquidity, JSBI.BigInt(0))) {
            throw Error("should not be 0 liquidity");
        }

        const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tickLower), inRangeLiquidity, tickLower);
        const amountStart = Number(new Position({ pool, liquidity, tickLower, tickUpper }).amount0.toExact());

        const results = [];
        
        for (let tick = tickLower; tick <= tickUpper; tick += 1) {
            const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tick), inRangeLiquidity, tick);

            const position = new Position({ pool, liquidity, tickLower, tickUpper });
            const token0 = Number(position.amount0.toExact());
            const token1 = Number(position.amount1.toExact());

            const lossToken1 = amountStart - token0 - token1 * Number(pool.token1Price.toSignificant(6)) / (1 + totalSwapLoss);
            // const lossToken0 = lossToken1 * Number(pool.token1Price.toSignificant(6));
            results.push({
                tick,
                token0,
                token1,
                price0: pool.token0Price.toSignificant(5),
                price1: pool.token1Price.toSignificant(6),
                deltaToken0: amountStart - token0,
                lossToken1,
            });
        }

        return results;
    }

    public async estimateSingleSideToken0APR(
        amount: JSBI,
        tickLower: number, 
        tickUpper: number, 
        secondsAgo: number, 
        blockTime: number,
        decimals0: number,
        decimals1: number,
    ): Promise<[number, number]> {
        const slot = await this.contract.slot0();

        const sqrtPriceX96 = JSBI.BigInt(slot.sqrtPriceX96.toString());
        const lowerSqrt = TickMath.getSqrtRatioAtTick(tickLower);
        const upperSqrt = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtPriceX96 < lowerSqrt || sqrtPriceX96 > upperSqrt) {
            return [0, 0];
        }

        const liquidity = maxLiquidityForAmounts(
            lowerSqrt,
            lowerSqrt,
            upperSqrt,
            amount,
            0,
            true
        );

        const [fee0, fee1] = await this.getFeeGrowth(liquidity, tickLower, tickUpper, secondsAgo, blockTime);
        let priceX96 = FullMath.mulDivRoundingUp(sqrtPriceX96, sqrtPriceX96, Q96_JSBI);
        priceX96 = JSBI.multiply(priceX96, JSBI.BigInt(Math.pow(10, decimals0 - decimals1)));

        const fee0In1 = FullMath.mulDivRoundingUp(JSBI.BigInt(fee0.toString()), priceX96, Q96_JSBI);
        const fee = JSBI.add(JSBI.BigInt(fee1.toString()), fee0In1);

        const a0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, upperSqrt, liquidity, false);
        const a1 = SqrtPriceMath.getAmount1Delta(lowerSqrt, sqrtPriceX96, liquidity, false);

        const principle0In1 = FullMath.mulDivRoundingUp(a0, priceX96, Q96_JSBI);
        const principle = JSBI.add(principle0In1, a1);

        // console.log("principle", principle.toString(), "fee", fee.toString());
    
        const multiplier = JSBI.BigInt(10000 * SECONDS_IN_A_YEAR / secondsAgo);
        return [Number(fee.toString()), Number(JSBI.divide(JSBI.multiply(fee, multiplier), principle)) / 10000];
    }

    public async estimateAPR(
        amount0: bigint, 
        amount1: bigint,
        tickLower: number, 
        tickUpper: number, 
        secondsAgo: number, 
        blockTime: number,
        decimals0: number,
        decimals1: number,
    ): Promise<number> {
        const slot = await this.contract.slot0();

        const sqrtPriceX96 = JSBI.BigInt(slot.sqrtPriceX96.toString());
        const lowerSqrt = TickMath.getSqrtRatioAtTick(tickLower);
        const upperSqrt = TickMath.getSqrtRatioAtTick(tickUpper);

        if (sqrtPriceX96 < lowerSqrt || sqrtPriceX96 > upperSqrt) {
            return 0;
        }

        const liquidity = maxLiquidityForAmounts(
            sqrtPriceX96,
            lowerSqrt,
            upperSqrt,
            JSBI.BigInt(amount0.toString()),
            JSBI.BigInt(amount1.toString()),
            true
        );

        const [fee0, fee1] = await this.getFeeGrowth(liquidity, tickLower, tickUpper, secondsAgo, blockTime);
        let priceX96 = FullMath.mulDivRoundingUp(sqrtPriceX96, sqrtPriceX96, Q96_JSBI);
        priceX96 = JSBI.multiply(priceX96, JSBI.BigInt(Math.pow(10, decimals0 - decimals1)));

        const fee0In1 = FullMath.mulDivRoundingUp(JSBI.BigInt(fee0.toString()), priceX96, Q96_JSBI);
        const fee = JSBI.add(JSBI.BigInt(fee1.toString()), fee0In1);

        const a0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, upperSqrt, liquidity, false);
        const a1 = SqrtPriceMath.getAmount1Delta(lowerSqrt, sqrtPriceX96, liquidity, false);

        const principle0In1 = FullMath.mulDivRoundingUp(a0, priceX96, Q96_JSBI);
        const principle = JSBI.add(principle0In1, a1);

        // console.log("principle", principle.toString(), "fee", fee.toString());
    
        const multiplier = JSBI.BigInt(10000 * SECONDS_IN_A_YEAR / secondsAgo);
        return Number(JSBI.divide(JSBI.multiply(fee, multiplier), principle)) / 10000;
    }

    async getFeeGrowthInside(
        tickLower: number,
        tickUpper: number,
        secondsAgo: number,
        blockTime: number
    ) {
        const latestBlockNumber = await this.contract.runner!.provider?.getBlockNumber();
        const blocks = Math.floor(secondsAgo / blockTime);
        const historyBlock = latestBlockNumber! - blocks;

        const slot = await this.contract.slot0({blockTag: historyBlock});

        const tickCurrent = slot.tick;
        // console.log(historyBlock, "latestBlockNumber", latestBlockNumber, tickCurrent);

        const tickLowerInfo = await this.contract.ticks(tickLower, {blockTag: historyBlock});
        const tickUpperInfo = await this.contract.ticks(tickUpper, {blockTag: historyBlock});

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
            JSBI.BigInt((await this.contract.feeGrowthGlobal0X128({blockTag: historyBlock})).toString()),
            JSBI.BigInt((await this.contract.feeGrowthGlobal1X128({blockTag: historyBlock})).toString()),
        );
        return [
            fee0Rate,
            fee1Rate
        ];
    }

    public async getFeeGrowth(liquidity: JSBI, tickLower: number, tickUpper: number, secondsAgo: number, blockTime: number): Promise<[BigInt, BigInt]> {
        const feeGrowthNow = await this.getFeeGrowthInside(tickLower, tickUpper, 0, blockTime);
        const feeGrowthBefore = await this.getFeeGrowthInside(tickLower, tickUpper, secondsAgo, blockTime);

        const fee0Growth = this.calculateFee(BigInt(feeGrowthNow[0].toString()), BigInt(feeGrowthBefore[0].toString()), BigInt(liquidity.toString()));
        const fee1Growth = this.calculateFee(BigInt(feeGrowthNow[1].toString()), BigInt(feeGrowthBefore[1].toString()), BigInt(liquidity.toString()));

        return [fee0Growth, fee1Growth];
    }

    public async address(): Promise<string> {
        return await this.contract.getAddress();
    }

    public runner(): ContractRunner {
        return this.contract.runner!;
    }


    calculateFee(feeGrowthInsideNow: bigint, feeGrowthInsideBefore: bigint, liquidity: bigint): bigint {
        return (feeGrowthInsideNow - feeGrowthInsideBefore) * liquidity / Q128;
    }

    getUniswapPositionKey(owner: string, tickLower: number, tickUpper: number): string {
        return solidityPackedKeccak256(['address', 'int24', 'int24'], [owner, tickLower, tickUpper]);
    }

    async tokenBalance(token: string): Promise<BigInt> {
        const caller = this.contract.runner! as Signer;
        const addressThis = await this.contract.getAddress();

        const tokenContract = await loadContract("IERC20", token, caller);
        return await tokenContract.balanceOf(addressThis);
    }

    static async tokenMetadata(token: string, provider: Provider): Promise<[string, number]> {
        const tokenContract = await loadContractForQuery("ERC20", token, provider);
        return [
            await tokenContract.name(),
            Number(await tokenContract.decimals())
        ]
    }
}
