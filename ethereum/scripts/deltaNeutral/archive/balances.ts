import { UniswapV3PoolUtil } from '../../UniswapPositionUitl';
import { ethers } from 'hardhat';
import JSBI from 'jsbi';

// all in one: 40210.25771302155
// wait:
//.   pos 1: 12560.28299019196
//.   pos 2: 14996.771309517306
//.   pos 3: 12620.438152550672
const pool = "0x46Cf1cF8c69595804ba91dFdd8d6b960c9B0a7C4";
const chainId = 56;

// 3405

//
const amount0 = JSBI.BigInt(ethers.parseEther("10601.6").toString());
const amount1 = JSBI.BigInt(ethers.parseEther("0.018149").toString());
const tickLower = -116530;
const tickUpper = -114920;
const openTick = -116249;

const liquidity = JSBI.BigInt("435630050959991694532");

async function main() {
  try {

    const position = await UniswapV3PoolUtil.fromPool(chainId, pool, ethers.provider);

    const results = position.balancesFromLiquidity(
      // amount0,
      // amount1,
      // openTick,
      liquidity,
      tickLower,
      tickUpper,
    );


    // const apr = await position.estimateSingleSideToken1APR(amount, tickLower, 120, 1.5, 18, 18);

    console.table(results[0]);
    // console.log(apr);

  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
