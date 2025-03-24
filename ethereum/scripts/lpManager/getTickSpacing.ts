import { ethers } from 'hardhat';
import { loadContract } from '../util';

const contractAddress = "0x90a54475d512b8f3852351611c38fad30a513491";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    const contract = await loadContract('UniswapV3Pool', contractAddress, deployer);
    console.log(await contract.tickSpacing());

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
