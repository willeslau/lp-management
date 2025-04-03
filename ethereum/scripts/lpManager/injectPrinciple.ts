import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const amount0 = ethers.parseEther("387.7");
const amount1 = ethers.parseEther("1087.46491");

const tokenPairId = 4;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.useCaller(deployer);
    
    await lpManager.injectPricinple(tokenPairId, amount0, amount1);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
