import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';
import { delay } from '../util';
import { Token } from '@uniswap/sdk-core';

function toEther(amount: bigint, decimals: number): Number {
  return Number(amount) / Math.pow(10, Number(decimals));
}

const pool = "0xEa27B3E61144f0417f27AeDaa1B9e46FA5a49ff1";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);

    const uniswapPoolInfo = await lpManager.uniswapPoolInfo(pool);

    console.log(uniswapPoolInfo);
    const token0 = new Token(56, uniswapPoolInfo.token0, uniswapPoolInfo.token0Decimals, '', '');
    const token1 = new Token(56, uniswapPoolInfo.token1, uniswapPoolInfo.token1Decimals, '', '');

    console.log("\n\n\n\n");

    while(true) {
      const monitor = await lpManager.getPositionFees(pool, token0, token1, uniswapPoolInfo.feeTier);
      
      if (monitor.position === undefined) {
        process.stdout.write(`\rcurrent tick: ${monitor.tickCurrent}, amount0: ${toEther(BigInt(monitor.principle.token0), 18).toFixed(3)}, amount1: ${toEther(BigInt(monitor.principle.token1), 18).toFixed(3)}`);
      } else {
        let s = `in range: ${monitor.position.tickLower <= monitor.tickCurrent && monitor.tickCurrent <= monitor.position.tickUpper}`;
        s = `${s}, tick: ${monitor.position.tickLower}, ${monitor.tickCurrent}(current), ${monitor.position.tickUpper}`;
        s = `${s}, fee0: ${toEther(monitor.fees[0], 18).toFixed(3)}`;
        s = `${s}, fee1: ${toEther(monitor.fees[1], 18).toFixed(3)}`;
        s = `${s}, amount0: ${monitor.principle.token0.toFixed(3)}`;
        s = `\r${s}, amount1: ${monitor.principle.token1.toFixed(3)}`;
        process.stdout.write(s);
        
      }

      await delay(3000);
    }


    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
