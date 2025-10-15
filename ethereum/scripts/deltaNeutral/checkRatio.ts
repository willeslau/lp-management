import { ethers } from 'hardhat';
import { fromNetwork } from './config';
import { Fraction } from '@uniswap/sdk-core';
import JSBI from 'jsbi';
 
const amount0 = JSBI.BigInt("33603855847991232");
const amount1 = JSBI.BigInt("63269157729169");

const targetRatio = new Fraction(amount0, amount1);
// 0.1% diff
const delta = new Fraction("1", "1000");

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const operator = await fromNetwork(deployer);

    console.log(await operator.isInRatio(targetRatio, delta));
    const [delta0, delta1] = await operator.tokenAmountDelta(amount0, amount1);

    console.log(delta0, delta1);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
