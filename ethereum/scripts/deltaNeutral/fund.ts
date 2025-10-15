import { ethers } from 'hardhat';
import { fromNetwork } from './config';

const amount0 = ethers.parseEther("65");
const amount1 = ethers.parseEther("0.1");

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const operator = await fromNetwork(deployer);
    await operator.injectFunds(amount0, amount1);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
