import { Provider } from 'ethers';
import { UniswapV3PoolUtil } from '../UniswapPositionUitl';
import { ethers } from 'hardhat';
import JSBI from 'jsbi';

const poolAddress = "0x172fcD41E0913e95784454622d1c3724f546f849";
const chainId = 56;

const poolTicks = [-65030];
const exitTicks = [-65060];
const tickDelta = 20;
const token0Amount = JSBI.BigInt(ethers.parseEther("3000").toString());

const trigger = [
  { tickLower: 0, tickUpper: -65052, triggerTick: 0 }
];
trigger[0].tickLower = trigger[0].tickUpper - tickDelta;
trigger[0].triggerTick = trigger[0].tickLower;

console.log(trigger);

async function main() {
  try {
    const simulator = await initFromPool(chainId, poolAddress, ethers.provider, trigger, token0Amount);

    let index = 0;
    while (true) {
      // const currentTick = await pool.poolTick();

      if (index === poolTicks.length) {
        break;
      }

      const currentTick = poolTicks[index];
      const exitTick = exitTicks[index];
      index += 1;

      // if (simulator.shouldRearrange(currentTick)) {
      //   continue;
      // }

      const newRange = simulator.nextBalanceRange(currentTick, exitTick);

      // const rebalancePosition = simulator.rebalance(currentTick, newRange);
      // rebalancePosition['currentTick'] = currentTick;
      // rebalancePosition['tickLower'] = newRange[0];
      // rebalancePosition['tickUpper'] = newRange[1];
      // stats.push(rebalancePosition);

      break;
    }

    // console.table(stats);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();

class Ratio {
  numerator: number;
  denominator: number;

  constructor(numerator: number, denominator: number) {
    this.numerator = numerator;
    this.denominator = denominator;
  }
}

interface Trigger {
  triggerTick: number,
  tickLower: number,
  tickUpper: number,
}

interface UniswapPosition {
  tickLower: number,
  tickUpper: number,
  liquidity: JSBI,
}

async function initFromPool(chainId: number, poolAddress: string, provider: Provider, nextTriggers: Trigger[], principle: JSBI): Promise<T0PPStrategySimulator> {
  const pool = await UniswapV3PoolUtil.fromPool(chainId, poolAddress, provider);
  return new T0PPStrategySimulator(pool, principle, nextTriggers);
}

/// Token 0 Principle Protection strategy (T0PP)
class T0PPStrategySimulator {
  readonly pool: UniswapV3PoolUtil;
  readonly principle: JSBI;

  position: UniswapPosition;
  
  // the last element is the current position range
  nextTriggers: Trigger[];

  constructor(pool: UniswapV3PoolUtil, principle: JSBI, nextTriggers: Trigger[]) {
    this.pool = pool;
    this.principle = principle;
    this.nextTriggers = nextTriggers;

    const trigger = this.currentTrigger();
    if (trigger === null) {
      throw Error("invalid triger length");
    }

    this.position = { 
      tickLower: trigger.tickLower,
      tickUpper: trigger.tickUpper,
      liquidity: this.pool.liquidity(principle, JSBI.BigInt(0), trigger.triggerTick, trigger.tickLower, trigger.tickUpper)
    };
  }

  currentTrigger(): Trigger | null {
    if (this.nextTriggers.length === 0) {
      return null;
    }

    const lastItemIndex = this.nextTriggers.length - 1;
    return this.nextTriggers[lastItemIndex];
  }

  public shouldRearrange(currentTick: number): boolean {
    // const [amount0, amount1] = 
    return true;
  }

  public tokenBalances(currentTick: number): [JSBI, JSBI] {
    return [JSBI.BigInt(0), JSBI.BigInt(0)];
  }

  public nextBalanceRange(currentTick: number, exitTick: number): [number, number] {
    if (exitTick > this.position.tickUpper) {
      throw Error("exit too late");
    }

    if (currentTick < this.position.tickUpper) {
      throw Error("no need to rebalance");
    }

    const [amount0, amount1] = this.pool.balancesAtTickFromLiquidity(this.position.liquidity, this.position.tickLower, this.position.tickUpper, exitTick);

    console.log("principle", JSBI.divide(this.principle, JSBI.BigInt(Math.pow(10, this.pool.token0.decimals).toString())).toString(), "amount0", amount0.toExact(), "amount1" , amount1.toExact());

    // assuming all ticks are negative
    const results = [];
    const openPositionTick = currentTick;
    const tickUpper = currentTick - 1;

    for (let tick = this.position.tickLower ; tick < currentTick - 1; tick += 1) {
      const tickLower = tick;
      const targetClosePositionTick = tickLower - 1;

      // console.log(openPositionTick, tickLower, tickUpper, targetClosePositionTick);
      const [newAmount0, newAmount1] = this.pool.balancesAtTickFromAmounts(JSBI.BigInt(0), amount1.quotient, openPositionTick, tickLower, tickUpper, targetClosePositionTick);
      results.push({
        openPositionTick, tickLower, tickUpper, targetClosePositionTick, amount0: (newAmount0.add(amount0)).toExact()
      });
    }

    console.table(results);

    return [0, 0];
  }
}
