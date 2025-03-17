import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../util';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const liquidityOwner = deployer.address;
    const balancer = deployer.address;
    const supportedTokenPairs = "0xBD05497f929013375da90768e1253bD03762a903";

    const contract = await deployContractWithDeployer(
      deployer,
      'UniswapV3LpManager',
      [supportedTokenPairs, liquidityOwner, balancer],
      false
    );

    await contract.waitForDeployment();
    console.log(`Contract deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
