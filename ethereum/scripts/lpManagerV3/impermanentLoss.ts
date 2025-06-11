import { UniswapV3PoolUtil } from '../UniswapPositionUitl';
import { ethers } from 'hardhat';
import JSBI from 'jsbi';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const chainId = 56;

const amount = JSBI.BigInt(ethers.parseEther("5000").toString());
const tickLower = -65091;
const tickUpper = -65045;

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

    const loss = position.singleSideToken0Losses(
      amount,
      tickLower,
      tickUpper,
      totalSwapLoss
    );

    const apr = await position.estimateSingleSideToken0APR(amount, tickLower, tickUpper, 120, 1.5, 18, 18);

    console.table(loss);
    console.log(apr);

  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
