import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';
import { lpManagerFromNetwork } from './config';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    console.log(await lpManager.listPositionKeys(0, 1000));

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
