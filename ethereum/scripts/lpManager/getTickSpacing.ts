import { ethers } from 'hardhat';
import { loadContract } from '../util';

const contractAddress = "0xaD27F113D7FaA5fBD99a8c384832B1D458D23034";

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
