import { Contract, ContractRunner, ethers, Interface, Signer, solidityPackedKeccak256 } from "ethers";
import { deployContractWithDeployer, deployUpgradeableContract, getBinancePrice, loadContract, loadContractForQuery } from "./util";
import { Pool, TickLibrary, FullMath, maxLiquidityForAmounts, TickMath, SqrtPriceMath, Position as UniswapPosition} from '@uniswap/v3-sdk';
import JSBI from "jsbi";
import { Fraction, Token } from "@uniswap/sdk-core";
import { UniswapV3PoolUtil } from "./UniswapPositionUitl";
import { artifacts } from "hardhat";

const Q128 = 340282366920938463463374607431768211456n;
const Q128_JSBI = JSBI.BigInt(Q128.toString());

const Q96 = 79228162514264337593543950336n;
const Q96_JSBI = JSBI.BigInt(Q96.toString());

const SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;
const DEFAULT_LIQUIDITY_FOR_ESTIMATION = JSBI.BigInt("500000000000000000000000");

const ONE_ETHER = JSBI.BigInt(ethers.parseEther("1").toString());
const ONE_ETHER_SQRT = JSBI.BigInt(ethers.parseUnits("1000000000", "wei").toString());
const SLIPPAGE_BASE = JSBI.BigInt(10000);
const SLIPPAGE_BASE_SQRT = JSBI.BigInt(100);

export interface QuoteParams {
    zeroForOne: boolean,
    priceLimitSqrt: bigint,
    priceLimit: bigint,
}

export interface Position {
    liquidity: number,
    tickLower: number,
    tickUpper: number,
    feeGrowthInside0LastX128: bigint,
    feeGrowthInside1LastX128: bigint,
    openPositionAmount0: bigint,
    openPositionAmount1: bigint,
    openPositionTick: number,
};

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

export interface DeployContractParams{
    swapMath: string | null,
    swapUtil: string | null,
    nonfungiblePositionMananger: string,
}

export class DeltaNeutral {
    operatorContract: Contract;
    uniswapPoolContract: Contract;
    pancakeLMPoolContract: Contract;
    token0: Token;
    token1: Token;
    feeTier: number;

    constructor(
        operatorContract: Contract,
        uniswapPoolContract: Contract,
        pancakeLMPoolContract: Contract,
        token0: Token,
        token1: Token,
        feeTier: number,
    ) {
        this.operatorContract = operatorContract;
        this.uniswapPoolContract = uniswapPoolContract;
        this.pancakeLMPoolContract = pancakeLMPoolContract;
        this.token0 = token0;
        this.token1 = token1;
        this.feeTier = feeTier;

    }

    public static async deploy(params: DeployContractParams, deployer: Signer, isSilent?: boolean): Promise<Contract> {
        if (isSilent === undefined) {
            isSilent = true;
        }

         if (params.swapMath === null || params.swapMath === undefined) {
            const c = await deployContractWithDeployer(
                deployer,
                'RebalanceSwapMath',
                [],
                isSilent
            );
            params.swapMath = await c.getAddress();
        }

        if (params.swapUtil === null || params.swapUtil === undefined) {
            const c = await deployContractWithDeployer(
                deployer,
                'SwapUtil',
                [],
                isSilent
            );
            params.swapUtil = await c.getAddress();
        }

        return await deployUpgradeableContract(
            deployer,
            'UniswapV3LpOperator',
            [
                params.nonfungiblePositionMananger,
                params.swapUtil,
                params.swapMath
            ],
            isSilent
        );
    }

    public static async fromPool(chainId: number, pool: string, lpOperator: string, caller: Signer): Promise<DeltaNeutral> {
        const operatorContract = await loadContract('UniswapV3LpOperator', lpOperator, caller);
        const poolContract = await loadContractForQuery('IUniswapV3Pool', pool, caller.provider!);

        const pancakePoolContract = await loadContractForQuery('IPancakeswapV3Pool', pool, caller.provider!);
        const lpPoolAddress = await pancakePoolContract.lmPool();
        const pancakeLMPoolContract = await loadContractForQuery('IPancakeswapLMPool', lpPoolAddress, caller.provider!);

        const token0Address = await poolContract.token0();
        const token1Address = await poolContract.token1();

        const [token1Name, token1Decimals] = await UniswapV3PoolUtil.tokenMetadata(token1Address, caller.provider!);
        const [token0Name, token0Decimals] = await UniswapV3PoolUtil.tokenMetadata(token0Address, caller.provider!);

        const token0 = new Token(chainId, token0Address, token0Decimals, token0Name, token0Name);
        const token1 = new Token(chainId, token1Address, token1Decimals, token1Name, token1Name);

        const feeTier = Number(await poolContract.fee());

        return new DeltaNeutral(operatorContract, poolContract, pancakeLMPoolContract, token0, token1, feeTier);
    }
    
    convertFeeToHumanReadble(feeRaw: bigint, liquidity: JSBI): JSBI {
        const feeConverted = JSBI.BigInt(feeRaw.toString());
        console.log("feeConverted", feeConverted.toString());
    
        return FullMath.mulDivRoundingUp(feeConverted, liquidity, Q128_JSBI);
    }

    public async hasPosition(): Promise<boolean> {
        try {
            await this.getPosition();
            return true;
        } catch {
            return false;
        }
    }

    public async close(deadline?: number): Promise<void> {
        deadline = deadline || Math.floor(Date.now() / 1000) + 100;

        const tx = await this.operatorContract.close(deadline);
        await tx.wait();
    }

    private async tokenPrice(symbol: string): Promise<number> {
        const query = `${symbol.toUpperCase()}USDT`;
        return await getBinancePrice(query);
    }

    public async estimateCakeAPR(
        tickLower: number,
        tickUpper: number,
        amount0: JSBI,
        amount1: JSBI,
        secondsAgo: number,
        blockTime: number,
    ): Promise<number> {
        const price0 = await this.tokenPrice(this.token0.symbol!);
        const price1 = await this.tokenPrice(this.token1.symbol!);
        const priceCake = await this.tokenPrice("cake");

        const slot0 = await this.uniswapPoolContract.slot0();
        const sqrtPriceX96 = JSBI.BigInt(slot0.sqrtPriceX96.toString());

        const positionLiquidity = maxLiquidityForAmounts(
            sqrtPriceX96, 
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0,
            amount1,
            true
        );

        const latestBlockNumber = await this.uniswapPoolContract.runner!.provider?.getBlockNumber();
        const blocks = Math.floor(secondsAgo / blockTime);
        const historyBlock = latestBlockNumber! - blocks;

        const growthRateInsideBefore = await this.pancakeLMPoolContract.getRewardGrowthInside(tickLower, tickUpper, {blockTag: historyBlock});
        const growthRateInside = await this.pancakeLMPoolContract.getRewardGrowthInside(tickLower, tickUpper);

        const PRICE_SCALE_NUMBER = 100000;
        const PRICE_SCALE_JSBI = JSBI.BigInt(PRICE_SCALE_NUMBER.toString());
        const multiplyTokenToPrice = (amount: JSBI, price: number, decimals: number): number =>  {
            const scaled = Math.floor(price * PRICE_SCALE_NUMBER);
            const scaledPrice = JSBI.BigInt(scaled.toString());

            const tmp = JSBI.divide(
                JSBI.multiply(scaledPrice, amount),
                JSBI.BigInt(Math.pow(10, decimals).toString())
            );
            return JSBI.toNumber(JSBI.divide(tmp, PRICE_SCALE_JSBI));
        }

        const principle = multiplyTokenToPrice(amount0, price0, this.token0.decimals) + multiplyTokenToPrice(amount1, price1, this.token1.decimals);

        const earningCakeQ128 = BigInt(growthRateInside - growthRateInsideBefore) * BigInt(positionLiquidity.toString());
        const earningCakePerYearPercentage = 100n * earningCakeQ128 / BigInt(secondsAgo) * BigInt(SECONDS_IN_A_YEAR) / Q128;

        const usd = multiplyTokenToPrice(JSBI.BigInt(earningCakePerYearPercentage.toString()), priceCake, 18);
        return usd / principle;
    }

    public async cakeAPR(tickLower: number, tickUpper: number, secondsAgo: number, blockTime: number): Promise<number> {
        const latestBlockNumber = await this.uniswapPoolContract.runner!.provider?.getBlockNumber();
        const blocks = Math.floor(secondsAgo / blockTime);
        const historyBlock = latestBlockNumber! - blocks;

        const growthRateInsideBefore = await this.pancakeLMPoolContract.getRewardGrowthInside(tickLower, tickUpper, {blockTag: historyBlock});
        const growthRateInside = await this.pancakeLMPoolContract.getRewardGrowthInside(tickLower, tickUpper);
        return (growthRateInside - growthRateInsideBefore);
    }

    public async quotePool(
        tickLower: number,
        tickUpper: number,
        /// base 1000
        slippage: JSBI,
    ): Promise<[QuoteParams, JSBI, JSBI]> {
        const slot0 = await this.uniswapPoolContract.slot0();
        return await this.quotePoolFromSlot0(slot0, tickLower, tickUpper, slippage);
    }

    public async quotePoolFromSlot0(
        slot0: { sqrtPriceX96: bigint, tick: bigint, },
        tickLower: number,
        tickUpper: number,
        /// base 1000
        slippage: JSBI,
    ): Promise<[QuoteParams, JSBI, JSBI]> {
        const params: any = {};

        const sqrtPriceX96 = JSBI.BigInt(slot0.sqrtPriceX96.toString());
        const tick = Number(slot0.tick);

        const pool = new Pool(
            this.token0,
            this.token1,
            // does not matter what value, dummy
            100,
            sqrtPriceX96,
            // does not matter, dummy value
            "100000",
            tick
        );

        let amount0;
        let amount1;
        try {
            const oldPosition = await this.getPosition();
            const oldUniswapPosition = new UniswapPosition({
                pool,
                // does not matter, dummy value
                liquidity: oldPosition.liquidity,
                tickLower: oldPosition.tickLower,
                tickUpper: oldPosition.tickUpper
            });

            amount0 = oldUniswapPosition.amount0.quotient;
            amount1 = oldUniswapPosition.amount1.quotient;
        } catch {
            amount0 = JSBI.BigInt((await this.tokenBalance(this.token0.address)).toString());
            amount1 = JSBI.BigInt((await this.tokenBalance(this.token1.address)).toString());
        }

        params.zeroForOne = await this.isZeroForOne(pool, amount0, amount1, tickLower, tickUpper);

        if (params.zeroForOne) {
            const num = JSBI.multiply(
                ONE_ETHER,
                JSBI.subtract(SLIPPAGE_BASE, slippage)
            );

            const numSqrt = JSBI.BigInt(Math.floor(Math.sqrt(JSBI.toNumber(num))));
            params.priceLimitSqrt = JSBI.divide(
                JSBI.multiply(numSqrt, sqrtPriceX96),
                JSBI.multiply(ONE_ETHER_SQRT, SLIPPAGE_BASE_SQRT),
            );

            // calculate price
            params.priceLimit = JSBI.divide(
                JSBI.multiply(pool.token0Price.numerator, num),
                JSBI.multiply(pool.token0Price.denominator, SLIPPAGE_BASE)
            );
        } else {
            const num = JSBI.multiply(
                ONE_ETHER,
                JSBI.add(SLIPPAGE_BASE, slippage)
            );

            const numSqrt = JSBI.BigInt(Math.floor(Math.sqrt(JSBI.toNumber(num))));
            params.priceLimitSqrt = JSBI.divide(
                JSBI.multiply(numSqrt, sqrtPriceX96),
                JSBI.multiply(ONE_ETHER_SQRT, SLIPPAGE_BASE_SQRT),
            );

            params.priceLimit = JSBI.divide(
                JSBI.multiply(pool.token0Price.numerator, num),
                JSBI.multiply(pool.token0Price.denominator, SLIPPAGE_BASE)
            );
        }

        params.priceLimit = JSBI.toNumber(params.priceLimit);
        params.priceLimitSqrt = BigInt(params.priceLimitSqrt.toString());
        return [params, amount0, amount1];
    }

    private async isZeroForOne(pool: Pool, amount0: JSBI, amount1: JSBI, tickLower: number, tickUpper: number): Promise<boolean> {
        if (JSBI.EQ(amount0, 0) && JSBI.EQ(amount1, 0)) {
            throw Error("both token amounts 0");
        }
        
        if (JSBI.EQ(amount0, 0)) {
            return false;
        }

        if (JSBI.EQ(amount1, 0)) {
            return true;
        }

        // Position
        const position = new UniswapPosition({
            pool,
            // does not matter, dummy value
            liquidity: "1000000000000000000",
            tickLower,
            tickUpper
        });

        const thresholdAmount0 = position.amount0.multiply(amount1.toString()).divide(position.amount1);
        return thresholdAmount0.lessThan(amount0);
    }

    public async swap(pool: string, tokenIn: string, params: { zeroForOne: boolean,  priceSqrtX96Limit: bigint, amountOutMin: bigint, amountIn: bigint }): Promise<void> {
        const addr = await this.operatorContract.swapUtil();
        const swapUtil = await loadContract("SwapUtil", addr, this.operatorContract.runner! as Signer);

        await this.increaseAllowanceIfNeeded(tokenIn, addr, params.amountIn);

        await swapUtil.swap(pool, tokenIn, { swapper: 0, ...params});
    }

    public async tokenAmountDelta(): Promise<[number, number, number]> {
        const position = await this.getPosition();
        return await this.tokenAmountDeltaFromPosition(position);
    }

    public async tokenAmountDeltaFromPosition(position: Position): Promise<[number, number, number]> {
        const slot = await this.uniswapPoolContract.slot0();

        const tick = Number(slot.tick);

        const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tick), 0, tick);

        const price = pool.priceOf(this.token1);

        let { liquidity, tickLower, tickUpper, openPositionAmount1 } = position;

        const uniswapPosition = new UniswapPosition({ pool, liquidity: Number(liquidity), tickLower: Number(tickLower), tickUpper: Number(tickUpper) });
        
        
        console.log("price ranges", uniswapPosition.token0PriceUpper.invert().toFixed(), price.toFixed(), uniswapPosition.token0PriceLower.invert().toFixed());
        
        // At tick upper, amount1 will be zero. At tick lower, position will all be token 1
        const currentAmount1 = uniswapPosition.amount1.quotient;

        const t = JSBI.BigInt(Number(openPositionAmount1));
        let delta1;
        if (JSBI.lessThan(currentAmount1, t)) {
            delta1 = JSBI.subtract(currentAmount1, t);
        } else {
            let pool2 = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tickUpper), 0, tickUpper);
            let uniswapPosition2 = new UniswapPosition({ pool: pool2, liquidity: Number(liquidity), tickLower: Number(tickLower), tickUpper: Number(tickUpper) });
            delta1 = JSBI.subtract(currentAmount1, t);

            const range = JSBI.subtract(uniswapPosition2.amount1.quotient, t);

            const deltaRatio = Number(1000000n * BigInt(delta1.toString()) / BigInt(range.toString())) / 1000000;
            // console.log("more token1", t.toString(), currentAmount1.toString(), uniswapPosition2.amount1.quotient.toString(), deltaRatio);
            return [
                Number(openPositionAmount1),
                JSBI.toNumber(currentAmount1),
                // Number(1000000n * BigInt(JSBI.subtract(amount0, a0).toString()) / openPositionAmount0) / 1000000,
                deltaRatio,
            ];
        }

        return [
            Number(openPositionAmount1),
            JSBI.toNumber(currentAmount1),
            // Number(1000000n * BigInt(JSBI.subtract(amount0, a0).toString()) / openPositionAmount0) / 1000000,
            Number(1000000n * BigInt(delta1.toString()) / openPositionAmount1) / 1000000,
        ];
    }

    public async isInRatio(targetRatio: Fraction, delta: Fraction): Promise<boolean> {
        const slot = await this.uniswapPoolContract.slot0();

        const tick = Number(slot.tick);

        const pool = new Pool(this.token0, this.token1, this.feeTier,  TickMath.getSqrtRatioAtTick(tick), 0, tick);

        let { liquidity, tickLower, tickUpper } = await this.getPosition();

        const position = new UniswapPosition({ pool, liquidity: Number(liquidity), tickLower: Number(tickLower), tickUpper: Number(tickUpper) });

        const amount0 = position.amount0.quotient;
        const amount1 = position.amount1.quotient;

        const ratio = new Fraction(amount0, amount1);
        
        let diff;
        if (ratio.greaterThan(targetRatio)) {
            diff = ratio.subtract(targetRatio).divide(targetRatio);
        } else {
            diff = targetRatio.subtract(ratio).divide(ratio);
        }

        console.log(
            "current ratio", ratio.toSignificant(10),
            "target ratio", targetRatio.toSignificant(10)
        );

        return diff < delta;
    }

    public async estimateAPR(
        tickLower: number, 
        tickUpper: number, 
        secondsAgo: number, 
        blockTime: number,
    ): Promise<number> {
        const slot = await this.uniswapPoolContract.slot0();

        const sqrtPriceX96 = JSBI.BigInt(slot.sqrtPriceX96.toString());
        const lowerSqrt = TickMath.getSqrtRatioAtTick(tickLower);
        const upperSqrt = TickMath.getSqrtRatioAtTick(tickUpper);

        if (JSBI.lessThan(sqrtPriceX96, lowerSqrt) || JSBI.greaterThan(sqrtPriceX96, upperSqrt)) {
            return 0;
        }

        const liquidity = DEFAULT_LIQUIDITY_FOR_ESTIMATION;

        const [fee0, fee1] = await this.getFeeGrowth(liquidity, tickLower, tickUpper, secondsAgo, blockTime);
        let priceX96 = FullMath.mulDivRoundingUp(sqrtPriceX96, sqrtPriceX96, Q96_JSBI);
        priceX96 = JSBI.multiply(priceX96, JSBI.BigInt(Math.pow(10, this.token0.decimals - this.token1.decimals)));

        const fee0In1 = FullMath.mulDivRoundingUp(JSBI.BigInt(fee0.toString()), priceX96, Q96_JSBI);
        const fee = JSBI.add(JSBI.BigInt(fee1.toString()), fee0In1);

        const a0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, upperSqrt, liquidity, false);
        const a1 = SqrtPriceMath.getAmount1Delta(lowerSqrt, sqrtPriceX96, liquidity, false);

        const principle0In1 = FullMath.mulDivRoundingUp(a0, priceX96, Q96_JSBI);
        const principle = JSBI.add(principle0In1, a1);

        // console.log("principle", principle.toString(), "fee", fee.toString());
    
        const multiplier = JSBI.BigInt(10000 * SECONDS_IN_A_YEAR / secondsAgo);
        return JSBI.toNumber((JSBI.divide(JSBI.multiply(fee, multiplier), principle))) / 100;
    }

    public async swapAndMint(
        quote: QuoteParams,
        tickLower: number,
        tickUpper: number,
        deadline?: number,
    ): Promise<any> {
        deadline = deadline || Math.floor(Date.now() / 1000) + 100;

        const tx = await this.operatorContract.swapAndMint(
            quote,
            await this.uniswapPoolContract.getAddress(),
            {
                poolFee: this.feeTier,
                token0: this.token0.address,
                token1: this.token1.address,
            },
            tickLower,
            tickUpper,
            deadline
        );
        const receipt = await tx.wait();

        const mintEvent: any = {};
        await this.parseLog(receipt.logs, (parsed: any) => {
            if (parsed.name === "Mint") {
                mintEvent.tickLower = parsed.args.tickLower;
                mintEvent.tickUpper = parsed.args.tickUpper;
                mintEvent.liquidity = parsed.args.amount;
                mintEvent.amount0 = parsed.args.amount0;
                mintEvent.amount1 = parsed.args.amount1;
            }
        });
        return mintEvent;
    }

    async getFeeGrowthInside(
        tickLower: number,
        tickUpper: number,
        secondsAgo: number,
        blockTime: number
    ) {
        const latestBlockNumber = await this.uniswapPoolContract.runner!.provider?.getBlockNumber();
        const blocks = Math.floor(secondsAgo / blockTime);
        const historyBlock = latestBlockNumber! - blocks;

        const slot = await this.uniswapPoolContract.slot0({blockTag: historyBlock});

        const tickCurrent = slot.tick;
        // console.log(historyBlock, "latestBlockNumber", latestBlockNumber, tickCurrent);

        const tickLowerInfo = await this.uniswapPoolContract.ticks(tickLower, {blockTag: historyBlock});
        const tickUpperInfo = await this.uniswapPoolContract.ticks(tickUpper, {blockTag: historyBlock});

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
            JSBI.BigInt((await this.uniswapPoolContract.feeGrowthGlobal0X128({blockTag: historyBlock})).toString()),
            JSBI.BigInt((await this.uniswapPoolContract.feeGrowthGlobal1X128({blockTag: historyBlock})).toString()),
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

    public useCaller(caller: Signer) {
        // @ts-ignore
        this.contract = this.contract.connect(caller);
    }

    public async withdraw(token: string): Promise<void> {
        await this.operatorContract.withdraw(token);
    }

    public async withdrawAmount(token: string, amount: bigint): Promise<void> {
        await this.operatorContract['withdraw(address,uint256)'](token, amount);
    }

    public async getPosition(): Promise<Position> {
        const position = await this.operatorContract.getPosition();

        const {liquidity, tickLower, tickUpper, feeGrowthInside0LastX128, feeGrowthInside1LastX128 } = position.position;
        const openPositionAmount0 = position.openPositionAmount0; 
        const openPositionAmount1 = position.openPositionAmount1;
        const openPositionTick = position.openPositionTick;

        return {
            liquidity: Number(liquidity),
            tickLower: Number(tickLower),
            tickUpper: Number(tickUpper),
            feeGrowthInside0LastX128,
            feeGrowthInside1LastX128,
            openPositionAmount0,
            openPositionAmount1,
            openPositionTick: Number(openPositionTick),
        };
    }

    public async priceSqrt(): Promise<bigint> {
        const slot = await this.uniswapPoolContract.slot0();
        console.log(await this.uniswapPoolContract.tickSpacing());
        return slot.sqrtPriceX96;
    }

    public async estimateLoss(tickLower: number, tickUpper: number, slippage: JSBI, token1Exposure: number): Promise<[number, number]> {
        const slot0 = await this.uniswapPoolContract.slot0();
        const [quote, principleAmount0, principleAmount1] = await this.quotePoolFromSlot0(slot0, tickLower, tickUpper, slippage);

        const poolUtil = new UniswapV3PoolUtil(this.uniswapPoolContract, this.token0, this.token1, this.feeTier);

        for (let tick = tickLower; tick < tickUpper; tick += 1) {
            poolUtil.balancesAtTickFromAmounts(
                principleAmount0,
                principleAmount1,


            )
        }

    }

    public async deriveTickRange(range: number): Promise<[number, number]> {
        const upperRange = Math.floor(Math.sqrt(range + 1) * 100000);
        const lowerRange = Math.floor(Math.sqrt(1 - range) * 100000);

        const [lower, upper] = await this.operatorContract.deriveTickRange(await this.uniswapPoolContract.getAddress(), upperRange, lowerRange);
        return [Number(lower), Number(upper)];
    }

    public async swapAndMintFromRange(
        quote: QuoteParams,
        range: number,
        deadline?: number,
    ): Promise<any> {
        deadline = deadline || Math.floor(Date.now() / 1000) + 100;

        const upperRange = Math.floor(Math.sqrt(range + 1) * 100000);
        const lowerRange = Math.floor(Math.sqrt(1 - range) * 100000);

        const gas = await this.operatorContract.estimateGas.swapAndMintFromRange(
            quote,
            await this.uniswapPoolContract.getAddress(),
            upperRange,
            lowerRange,
            {
                poolFee: this.feeTier,
                token0: this.token0.address,
                token1: this.token1.address,
            },
            deadline
        );
        console.log(gas);
        throw "";
        const tx = await this.operatorContract.swapAndMintFromRange(
            quote,
            await this.uniswapPoolContract.getAddress(),
            upperRange,
            lowerRange,
            {
                poolFee: this.feeTier,
                token0: this.token0.address,
                token1: this.token1.address,
            },
            deadline
        );
        const receipt = await tx.wait();

        const mintEvent: any = {};
        await this.parseLog(receipt.logs, (parsed: any) => {
            if (parsed.name === "Mint") {
                mintEvent.tickLower = parsed.args.tickLower;
                mintEvent.tickUpper = parsed.args.tickUpper;
                mintEvent.liquidity = parsed.args.amount;
                mintEvent.amount0 = parsed.args.amount0;
                mintEvent.amount1 = parsed.args.amount1;
            }
        });
        return mintEvent;
    }

    public async getPositionFees(): Promise<Monitor> {
        const position = await this.getPosition();

        const slot = await this.uniswapPoolContract.slot0();

        const tickLower = position.tickLower;
        const tickCurrent = slot.tick;
        const tickUpper = position.tickUpper;

        const tickLowerInfo = await this.uniswapPoolContract.ticks(tickLower);
        const tickUpperInfo = await this.uniswapPoolContract.ticks(tickUpper);

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
            JSBI.BigInt((await this.uniswapPoolContract.feeGrowthGlobal0X128()).toString()),
            JSBI.BigInt((await this.uniswapPoolContract.feeGrowthGlobal1X128()).toString()),
        );

        const fee0 = this.calculateFee(BigInt(fee0Rate.toString()), BigInt(position.feeGrowthInside0LastX128), BigInt(position.liquidity));
        const fee1 = this.calculateFee(BigInt(fee1Rate.toString()), BigInt(position.feeGrowthInside1LastX128), BigInt(position.liquidity));

        const sqrtPriceX96 = slot.sqrtPriceX96;
        const liquidity = BigInt(position.liquidity);

        if (liquidity !== 0n) {
            const uniswapP = new UniswapPosition({
                pool: new Pool(this.token0, this.token1, this.feeTier, JSBI.BigInt(sqrtPriceX96.toString()), JSBI.BigInt(0), Number(tickCurrent)),
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
                token0: Number(await this.tokenBalance(await this.token0.address)),
                token1: Number(await this.tokenBalance(await this.token1.address)),
            }
            return {
                position: undefined,
                tickCurrent,
                fees: [BigInt(0), BigInt(0)],
                principle,
            }
        }
    }

    private calculateFee(feeGrowthInsideNow: bigint, feeGrowthInsideBefore: bigint, liquidity: bigint): bigint {
        return (feeGrowthInsideNow - feeGrowthInsideBefore) * liquidity / Q128;
    }

    public async tickSpacing(): Promise<Number> {
        const tickSpacing = await this.uniswapPoolContract.tickSpacing();
        return Number(tickSpacing);
    }

    async tokenBalance(token: string): Promise<BigInt> {
        const caller = this.operatorContract.runner! as Signer;
        const addressThis = await this.operatorContract.getAddress();

        const tokenContract = await loadContract("IERC20", token, caller);
        return await tokenContract.balanceOf(addressThis);
    }

    public async injectFunds(amount0: bigint, amount1: bigint): Promise<void> {
        const addr = await this.operatorContract.getAddress();

        if (amount0 > 0) {
            const tokenContract = await loadContract("IERC20", this.token0.address, this.operatorContract.runner! as Signer);
            const tx = await tokenContract.transfer(addr, amount0);
            await tx.wait();
        }

        if (amount1 > 0) {
            const tokenContract = await loadContract("IERC20", this.token1.address, this.operatorContract.runner! as Signer);
            const tx = await tokenContract.transfer(addr, amount1);
            await tx.wait();
        }
    }

    async parseLog<T>(logs: any[], filter: (log: any) => void): Promise<void> {
        const uniswapPool = new Interface((await artifacts.readArtifact("IUniswapV3Pool")).abi);
        for (const log of logs) {
            let parsed = null;

            try {
                parsed = this.operatorContract.interface.parseLog(log)!;
            } catch {
              // Skip logs that don't match the interface
            }

            try {
                if (parsed === null) {
                    parsed = uniswapPool.parseLog(log)!;
                }
            } catch {
              // Skip logs that don't match the interface
            }

            if (parsed === null) { continue; }

            filter(parsed);
        }
    }

    public async increaseAllowanceIfNeeded(token: string, spender: string, amount: bigint): Promise<void> {
        const caller = this.operatorContract.runner! as Signer;

        const tokenContract = await loadContract("IERC20", token, caller);
        const currentAllowance = await tokenContract.allowance(await caller.getAddress(), spender);

        if (currentAllowance >= amount) {
            return;
        }

        const tx = await tokenContract.approve(spender, amount);
        await tx.wait();
    }
}
