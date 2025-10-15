import { ethers } from 'hardhat';
import { networkConfig } from './config';
import { DeltaNeutral } from '../DeltaNeutral';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const config = networkConfig();

    const contract = await DeltaNeutral.deploy(config.deployment, deployer, false);

    await contract.waitForDeployment();
    console.log(`Delta neutral deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
