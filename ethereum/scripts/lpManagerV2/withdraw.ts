import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.withdraw("0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c");

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
