import { Contract, ContractRunner, Signer, solidityPackedKeccak256, ZeroAddress } from "ethers";
import { loadContract, loadContractForQuery } from "./util";
import { Pool, Position as UniswapPool, TickLibrary, FullMath } from '@uniswap/v3-sdk';
import JSBI from "jsbi";
import { Token } from "@uniswap/sdk-core";

const Q128 = 340282366920938463463374607431768211456n;
const RANGE_DENOMINATOR = 100000;
const Q128_JSBI = JSBI.BigInt(Q128.toString());

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

        return FullMath.mulDivRoundingUp(feeConverted, liquidity, Q128_JSBI);
    }

    public async getFeeGrowthNow(pool: string, tickLower: number, tickUpper: number): Promise<bigint> {
        return await this.uniswapUtil.getFeeGrowthInside(pool, tickLower, tickUpper);
    }

    public async getFeeGrowth(pool: string, liquidity: BigInt, tickLower: number, tickUpper: number, secondsAgo: number, blockTime: number): Promise<[bigint, bigint]> {
        const feeGrowthNow = await this.uniswapUtil.getFeeGrowthInside(pool, tickLower, tickUpper);
        
        const latestBlockNumber = await this.contract.runner!.provider?.getBlockNumber();
        const blocks = Math.floor(secondsAgo / blockTime);
        const historyBlock = latestBlockNumber! - blocks;

        const feeGrowthBefore = await this.uniswapUtil.getFeeGrowthInside(pool, tickLower, tickUpper, {blockTag: historyBlock});

        console.log("now vs before", feeGrowthNow, feeGrowthBefore);

        const liquidityJSBI = JSBI.BigInt(liquidity.toString());
        const fee0Growth = this.convertFeeToHumanReadble(BigInt(feeGrowthNow[0] - feeGrowthBefore[0]), liquidityJSBI);
        const fee1Growth = this.convertFeeToHumanReadble(BigInt(feeGrowthNow[1] - feeGrowthBefore[1]), liquidityJSBI);

        return [BigInt(fee0Growth.toString()), BigInt(fee1Growth.toString())];
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

    // private parsePositionChangedLog(logs: any[]): VaultPositionChangedEvent | null {
    //     for (const log of logs) {
    //         try {
    //           const parsed = this.contract.interface.parseLog(log)!;
    //           if (parsed.name === "VaultPositionChanged") {
    //             const { liquidityOwner, vaultId, change, amount0, amount1 } = parsed.args;
        
    //             return {
    //               liquidityOwner,
    //               vaultId: Number(vaultId),
    //               change: change as PositionChange,
    //               amount0: BigInt(amount0.toString()),
    //               amount1: BigInt(amount1.toString()),
    //             };
    //           }
    //         } catch {
    //           // Skip logs that don't match the interface
    //         }
    //     }
        
    //     return null; // No matching event found
    // }

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
