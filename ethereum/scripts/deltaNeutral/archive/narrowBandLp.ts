import { Fraction } from '@uniswap/sdk-core';
import { UniswapV3PoolUtil } from '../UniswapPositionUitl';
import { ethers } from 'hardhat';
import JSBI from 'jsbi';

const BASE = 10000000000;

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const chainId = 56;

// 3405
const amount = JSBI.BigInt(ethers.parseEther("5.714").toString());
const priceRange = 0.0011965491830454589;

async function main() {
  try {

    const position = await UniswapV3PoolUtil.fromPool(chainId, pool, ethers.provider);

    const fraction = new Fraction(Math.floor(priceRange * BASE), BASE);
    const loss = position.singleSideNarrowBandToken1Analysis(amount, fraction, 60, 1.5, 300, 18, 18);


    console.table(loss);

  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
