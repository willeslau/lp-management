import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../util';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await deployContractWithDeployer(
      deployer,
      'SwapUtil',
      [],
      false
    );

    await contract.waitForDeployment();
    console.log(`SwapUtil deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
