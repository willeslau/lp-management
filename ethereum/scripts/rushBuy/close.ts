import { ethers } from 'hardhat';
import { rushBuyFromNetwork } from './config';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const rushBuy = await rushBuyFromNetwork(deployer);
    await rushBuy.closePosition();

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
