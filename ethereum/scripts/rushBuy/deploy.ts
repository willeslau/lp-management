import { ethers } from 'hardhat';
import { deployUpgradeableContract } from '../util';
import { networkConfig } from './config';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const config = networkConfig();

    if (config.swapUtil === undefined) {
      throw Error(`Swap uitl not deployed `);
    }

    const contract = await deployUpgradeableContract(
      deployer,
      'RushBuy',
      [config.swapUtil],
      false
    );

    await contract.waitForDeployment();
    console.log(`RushBuy deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
