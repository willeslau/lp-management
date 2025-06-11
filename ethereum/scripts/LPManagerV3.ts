import { Contract, ContractRunner, Signer, solidityPackedKeccak256 } from "ethers";
import { loadContract, loadContractForQuery } from "./util";
import { Pool, Position as UniswapPool, TickLibrary, FullMath, maxLiquidityForAmounts, TickMath, SqrtPriceMath } from '@uniswap/v3-sdk';
import JSBI from "jsbi";
import { Token } from "@uniswap/sdk-core";

const Q128 = 340282366920938463463374607431768211456n;
const RANGE_DENOMINATOR = 100000;
const Q128_JSBI = JSBI.BigInt(Q128.toString());

const Q96 = 79228162514264337593543950336n;
const Q96_JSBI = JSBI.BigInt(Q96.toString());

const SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

export interface UniswapPoolInfo {
    token0: string,
    token0Decimals: number,
    token1: string,
    token1Decimals: number,
    feeTier: number,
    tickSpacing: number,
}

export interface  Position {
    tickLower: number;  // int24
    tickUpper: number;  // int24
    liquidity: bigint;
}

export interface TokenAmount {
    token0: number;
    token1: number;
}

export interface Monitor {
    position: Position | undefined,
    tickCurrent: bigint,
    fees: [bigint, bigint],
    principle: TokenAmount,
}

export class LPManagerV3 {
    contract: Contract;
    uniswapUtil: Contract;

    constructor(contract: Contract, uniswapUtil: Contract) {
        this.contract = contract;
        this.uniswapUtil = uniswapUtil;
    }

    public static async fromConfig(caller: Signer, lpManager: string, uniswapUtil: string): Promise<LPManagerV3> {
        const lp = await loadContract("UniswapV3LpManagerV3", lpManager, caller);
        const ut = await loadContract("UniswapUtil", uniswapUtil, caller);
        return new LPManagerV3(lp, ut);
    }

    convertFeeToHumanReadble(feeRaw: bigint, liquidity: JSBI): JSBI {
        const feeConverted = JSBI.BigInt(feeRaw.toString());
        console.log("feeConverted", feeConverted.toString());
    
        return FullMath.mulDivRoundingUp(feeConverted, liquidity, Q128_JSBI);
    }

    public async getFeeGrowthNow(pool: string, tickLower: number, tickUpper: number): Promise<bigint> {
        return await this.uniswapUtil.getFeeGrowthInside(pool, tickLower, tickUpper);
    }

    public async estimateAPR(
        pool: string, 
        amount0: bigint, 
        amount1: bigint,
        tickLower: number, 
        tickUpper: number, 
        secondsAgo: number, 
        blockTime: number,
        decimals0: number,
        decimals1: number,
    ): Promise<number> {
        const uniswapContract = await loadContractForQuery('IUniswapV3Pool', pool, this.contract.runner!);
        const slot = await uniswapContract.slot0();

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

        const [fee0, fee1] = await this.getFeeGrowth(pool, liquidity, tickLower, tickUpper, secondsAgo, blockTime);
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

    public async estimateSingleSideAPR(
        pool: string, 
        amount0: bigint, 
        amount1: bigint,
        tickRange: number,
        secondsAgo: number, 
        blockTime: number,
        decimals0: number,
        decimals1: number,
    ): Promise<number> {
        const uniswapContract = await loadContractForQuery('IUniswapV3Pool', pool, this.contract.runner!);
        const slot = await uniswapContract.slot0();

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

        const [fee0, fee1] = await this.getFeeGrowth(pool, liquidity, tickLower, tickUpper, secondsAgo, blockTime);
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
        pool: string,
        tickLower: number,
        tickUpper: number,
        secondsAgo: number,
        blockTime: number
    ) {
        const latestBlockNumber = await this.contract.runner!.provider?.getBlockNumber();
        const blocks = Math.floor(secondsAgo / blockTime);
        const historyBlock = latestBlockNumber! - blocks;

        const uniswapContract = await loadContractForQuery('IUniswapV3Pool', pool, this.contract.runner!);
        const slot = await uniswapContract.slot0({blockTag: historyBlock});

        const tickCurrent = slot.tick;
        // console.log(historyBlock, "latestBlockNumber", latestBlockNumber, tickCurrent);

        const tickLowerInfo = await uniswapContract.ticks(tickLower, {blockTag: historyBlock});
        const tickUpperInfo = await uniswapContract.ticks(tickUpper, {blockTag: historyBlock});

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
            JSBI.BigInt((await uniswapContract.feeGrowthGlobal0X128({blockTag: historyBlock})).toString()),
            JSBI.BigInt((await uniswapContract.feeGrowthGlobal1X128({blockTag: historyBlock})).toString()),
        );
        return [
            fee0Rate,
            fee1Rate
        ];
    }

    public async getFeeGrowth(pool: string, liquidity: JSBI, tickLower: number, tickUpper: number, secondsAgo: number, blockTime: number): Promise<[BigInt, BigInt]> {
        const feeGrowthNow = await this.getFeeGrowthInside(pool, tickLower, tickUpper, 0, blockTime);
        const feeGrowthBefore = await this.getFeeGrowthInside(pool, tickLower, tickUpper, secondsAgo, blockTime);

        const fee0Growth = this.calculateFee(BigInt(feeGrowthNow[0].toString()), BigInt(feeGrowthBefore[0].toString()), BigInt(liquidity.toString()));
        const fee1Growth = this.calculateFee(BigInt(feeGrowthNow[1].toString()), BigInt(feeGrowthBefore[1].toString()), BigInt(liquidity.toString()));

        // console.log("now vs before", fee0Growth.toString(), fee1Growth.toString());

        return [fee0Growth, fee1Growth];
    }

    public async getPosition(pool: string): Promise<Position> {
        return await this.contract.positions(pool);
    }

    public async getPositionInfo(pool: string): Promise<[Position, boolean]> {
        return await this.contract.getPoolPositionInfo(pool);
    }

    public async closePosition(pool: string): Promise<void> {
        const position = await this.getPosition(pool);
        if (position.liquidity == BigInt(0)) { return; }

        const tx = await this.contract.closePosition(
            pool,
            {
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                liquidity: position.liquidity
            }
        );
        await tx.wait();
    }

    public async rebalance(pool: String, range: number): Promise<void> {
        const rangeInBase = range * RANGE_DENOMINATOR;
        const tx = await this.contract.rebalance(pool, rangeInBase);
        const receipt = await tx.wait();
        console.log(receipt);
    }

    public useCaller(caller: Signer) {
        // @ts-ignore
        this.contract = this.contract.connect(caller);
    }

    public async withdraw(token: string): Promise<void> {
        await this.contract.withdraw(token);
    }

    public async withdrawAmount(token: string, amount: bigint): Promise<void> {
        await this.contract['withdraw(address,uint256)'](token, amount);
    }

    public async address(): Promise<string> {
        return await this.contract.getAddress();
    }

    public runner(): ContractRunner {
        return this.contract.runner!;
    }

    public async getPositionFees(pool: string, token0: Token, token1: Token, feeTier: number): Promise<Monitor> {
        const position = await this.getPosition(pool);

        const uniswapContract = await loadContractForQuery('IUniswapV3Pool', pool, this.contract.runner!);
        const slot = await uniswapContract.slot0();

        const tickLower = position.tickLower;
        const tickCurrent = slot.tick;
        const tickUpper = position.tickUpper;

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

        const uniswapPositioKey = await this.getUniswapPositionKey(position.tickLower, position.tickUpper);
        const uniswapPosition = await uniswapContract.positions(uniswapPositioKey);

        const fee0 = this.calculateFee(BigInt(fee0Rate.toString()), BigInt(uniswapPosition.feeGrowthInside0LastX128), uniswapPosition.liquidity);
        const fee1 = this.calculateFee(BigInt(fee1Rate.toString()), BigInt(uniswapPosition.feeGrowthInside1LastX128), uniswapPosition.liquidity);

        const sqrtPriceX96 = slot.sqrtPriceX96;
        const inRangeLiquidity = await uniswapContract.liquidity();
        const liquidity = uniswapPosition.liquidity;

        if (liquidity !== BigInt(0)) {
            const uniswapP = new UniswapPool({
                pool: new Pool(token0, token1, feeTier, JSBI.BigInt(sqrtPriceX96.toString()), JSBI.BigInt(inRangeLiquidity.toString()), Number(tickCurrent)),
                liquidity: JSBI.BigInt(liquidity.toString()),
                tickLower: Number(tickLower),
                tickUpper: Number(tickUpper),
            });
            return {
                position,
                tickCurrent,
                fees: [fee0, fee1],
                principle: {
                    token0: Number(uniswapP.amount0.toExact()),
                    token1: Number(uniswapP.amount1.toExact()),
                }
            }
        } else {
            const principle = {
                token0: Number(await this.tokenBalance(await uniswapContract.token0())),
                token1: Number(await this.tokenBalance(await uniswapContract.token1())),
            }
            return {
                position: undefined,
                tickCurrent,
                fees: [BigInt(0), BigInt(0)],
                principle,
            }
        }
    }

    calculateFee(feeGrowthInsideNow: bigint, feeGrowthInsideBefore: bigint, liquidity: bigint): bigint {
        return (feeGrowthInsideNow - feeGrowthInsideBefore) * liquidity / Q128;
    }

    public async uniswapPoolInfo(pool: string): Promise<UniswapPoolInfo> {
        const caller = this.contract.runner! as Signer;

        const uniswapContract = await loadContractForQuery('IUniswapV3Pool', pool, this.contract.runner!);
        const feeTier = await uniswapContract.fee();
        const tickSpacing = await uniswapContract.tickSpacing();

        const token0 = await uniswapContract.token0();
        const token1 = await uniswapContract.token1();

        const token0Contract = await loadContract("ERC20", token0, caller);
        const token1Contract = await loadContract("ERC20", token1, caller);
        
        const token0Decimals = await token0Contract.decimals();
        const token1Decimals = await token1Contract.decimals();

        return {
            token0,
            token0Decimals: Number(token0Decimals),
            token1,
            token1Decimals: Number(token1Decimals),
            feeTier: Number(feeTier),
            tickSpacing,
        };
    }

    async getUniswapPositionKey(tickLower: number, tickUpper: number): Promise<string> {
        const owner = await this.contract.getAddress();
        return solidityPackedKeccak256(['address', 'int24', 'int24'], [owner, tickLower, tickUpper]);
    }

    async tokenBalance(token: string): Promise<BigInt> {
        const caller = this.contract.runner! as Signer;
        const addressThis = await this.contract.getAddress();

        const tokenContract = await loadContract("IERC20", token, caller);
        return await tokenContract.balanceOf(addressThis);
    }
}
