import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../util';
import { networkConfig } from './config';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const liquidityOwner = deployer.address;
    const balancer = "0x4FDA8F3BB6b42C8Acbd93728E9eb9C5099f1c47b";

    const config = networkConfig();

    if (config.uniswapUtil === undefined) {
      const uniswapUtil = await deployContractWithDeployer(
        deployer,
        'UniswapUtil',
        [],
        false
      );
      console.log(`UniswapUtil deployed to ${await uniswapUtil.getAddress()}`);
    }

    const contract = await deployContractWithDeployer(
      deployer,
      'UniswapV3LpManager',
      [config.supportedTokenPair, liquidityOwner, balancer],
      false
    );

    await contract.waitForDeployment();
    console.log(`UniswapV3LpManager deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
