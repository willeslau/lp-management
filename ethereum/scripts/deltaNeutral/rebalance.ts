import { ethers } from 'hardhat';
import { fromNetwork } from './config';
import JSBI from 'jsbi';
import { Token } from '@uniswap/sdk-core';

const token0 = new Token(56, "0x55d398326f99059fF775485246999027B3197955", 18, "T0", "T0");
const token1 = new Token(56, "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", 18, "T0", "T0");
const tickLower = -65093;
const tickUpper = -64393;
const slippage = JSBI.BigInt(50); // 0.5%

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const operator = await fromNetwork(deployer);

    const quote = await operator.quotePool(
      token0,
      token1,
      tickLower,
      tickUpper,
      slippage
    );

    console.log(quote);

    const deadline = Math.floor(Date.now() / 1000) + 10;
    await operator.swapAndMint(quote, tickLower, tickUpper, deadline);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
