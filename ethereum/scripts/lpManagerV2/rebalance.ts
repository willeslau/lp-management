import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';
import { Swapper } from '../LPManagerV2';

const params = {};

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);

    lpManager.rebalance({
      vaultId: 0,
      swap: {
        swapper: Swapper.UniswapPool,
        zeroForOne: false,
        priceSqrtX96Limit: 0n,
        amountOutMin: ethers.parseEther("201900"),
        amountIn: 0n
      },
      mint: {
        tickLower: 0,
        tickUpper: 0,
        amount0Min: 0n,
        amount1Min: 0n
      }
    });

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
