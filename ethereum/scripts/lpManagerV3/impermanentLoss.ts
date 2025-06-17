import { UniswapV3PoolUtil } from '../UniswapPositionUitl';
import { ethers } from 'hardhat';
import JSBI from 'jsbi';

// all in one: 40210.25771302155
// wait:
//.   pos 1: 12560.28299019196
//.   pos 2: 14996.771309517306
//.   pos 3: 12620.438152550672
const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const chainId = 56;

// 3405

//
const amount = JSBI.BigInt(ethers.parseEther("6").toString());
const tickLower = -64986;
const tickUpper = -64900;

const swapSlippage = 0.0003;
const feeRate = 0.0001;
const totalSwapLoss = swapSlippage + feeRate;

async function main() {
  try {

    const position = await UniswapV3PoolUtil.fromPool(chainId, pool, ethers.provider);

    // const balances = position.balances(
    //   amount0,
    //   amount1,
    //   tickUpper,
    //   tickLower,
    //   tickUpper,
    // );

    const loss = position.singleSideToken1Summary(
      amount,
      tickLower,
      tickUpper
    );

    // const apr = await position.estimateSingleSideToken1APR(amount, tickLower, 120, 1.5, 18, 18);

    console.table(loss[0]);
    // console.log(apr);

  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
