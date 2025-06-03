import { ethers } from 'hardhat';
import { loadContract } from './util';

const ERC20Token = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c";
const spender = "0x5dE6A737F580235E1B81a54ca4eE32ce52802aeD";
const amount = ethers.parseEther("1");

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);
    
    const token = await loadContract("ERC20", ERC20Token, deployer);
    await token.approve(spender, amount);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
