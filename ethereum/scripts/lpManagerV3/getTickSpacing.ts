import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { TickLibrary } from '@uniswap/v3-sdk';

const contractAddress = "0x71f5a8F7d448E59B1ede00A19fE59e05d125E742";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    const contract = await loadContract('UniswapV3Pool', contractAddress, deployer);
    console.log(await contract.tickSpacing());
    console.log(await contract.ticks(7500));

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
