import { ethers } from 'hardhat';
import { deployContractWithDeployer } from '../util';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const nft = await deployContractWithDeployer(deployer, 'UniswapV3TokenPairs', [], true);

    await nft.waitForDeployment();
    console.log(`Contract deployed to ${await nft.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
