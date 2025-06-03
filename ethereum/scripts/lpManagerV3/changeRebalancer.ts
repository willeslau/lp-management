import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const newRebalancer = "0x4FDA8F3BB6b42C8Acbd93728E9eb9C5099f1c47b";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.useCaller(deployer);
    
    await lpManager.innerContract.setBalancer(newRebalancer);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
