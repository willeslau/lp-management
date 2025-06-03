import { ethers } from 'hardhat';
import { deployContractWithDeployer } from './util';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await deployContractWithDeployer(deployer, 'TestToken', [
        'wBTC',
        'wBTC',
        await deployer.getAddress(),
        ethers.parseEther("10000000000000000")
    ], false);

    // merlinTestnet: 0x996dAa9f671EA1BA27dd3DFa69857f59694BdFad
    await contract.waitForDeployment();
    console.log(`Contract deployed to ${await contract.getAddress()}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
