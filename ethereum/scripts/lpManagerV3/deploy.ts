import { ethers } from 'hardhat';
import { deployContractWithDeployer, deployUpgradeableContract } from '../util';
import { networkConfig } from './config';

const liquidityOwner = "0x75EE99e3a4D487a34F4ab0449B4895Fed79e23E2";
const balancer = "0x4FDA8F3BB6b42C8Acbd93728E9eb9C5099f1c47b";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

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

    // const contract = await deployUpgradeableContract(
    //   deployer,
    //   'UniswapV3LpManagerV3',
    //   [liquidityOwner, balancer],
    //   false
    // );

    // await contract.waitForDeployment();
    // console.log(`UniswapV3LpManagerV3 deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
