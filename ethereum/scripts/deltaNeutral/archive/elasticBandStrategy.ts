import { UniswapV3PoolUtil } from '../UniswapPositionUitl';
import { ethers } from 'hardhat';
import JSBI from 'jsbi';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const chainId = 56;

const initialBorrowed = 7.5;

const token1BorrowAmount = JSBI.BigInt(ethers.parseEther(initialBorrowed.toString()).toString());
const tickRange = 20;
const deltaTick = 2;

const swapSlippage = 0.0003;
const feeRate = 0.0001;
const totalSwapLoss = swapSlippage + feeRate;

async function main() {
  try {

    const position = await UniswapV3PoolUtil.fromPool(chainId, pool, ethers.provider);

    
    const currentTick = await position.poolTick();
    // const tickLower = currentTick - 1;
    // const tickUpper = currentTick - 1 + tickRange;
    const tickLower = -65092;
    const tickUpper = -65054;
    console.log("tickLower", tickLower, "tickUpper", tickUpper);

    const sellToken1 = position.singleSideToken1Summary(
      token1BorrowAmount,
      tickLower,
      tickUpper,
      totalSwapLoss
    );
    console.table(sellToken1);

    const token0Balance = sellToken1[0].token0;

    const buyToken1 = position.singleSideToken0Summary(
      JSBI.BigInt(ethers.parseEther(token0Balance.toString()).toString()),
      tickLower + deltaTick,
      tickUpper + deltaTick,
      totalSwapLoss
    );

    const token1FinalBalance = buyToken1[buyToken1.length - 1].token1;

    console.table(buyToken1);
    console.log("net gain", token1FinalBalance - initialBorrowed);

  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();


interface Target {
  initialTargetAPR: number,
  
}

class ElasticBandStrategySimulator {

  public init(currentTick: number, tickLower: number, tickUpper: number, amount0: JSBI, amount1: JSBI) {

  }
}