import { ethers } from 'hardhat';
import { networkConfig } from './config';
import { upgradeableContract } from '../util';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const config = networkConfig();

    await upgradeableContract(
      deployer,
      config.lpManager!,
      'UniswapV3LpManagerV3',
      false
  );
  
    const afterBalance = await ethers.provider.getBalance(deployer);
    console.log(`After Account balance: ${afterBalance.toString()}, It cost ${balance - afterBalance}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
