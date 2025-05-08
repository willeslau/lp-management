import { ethers } from 'hardhat';
import { rushBuyFromNetwork } from './config';

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const rushBuy = await rushBuyFromNetwork(deployer);
    await rushBuy.contract.withdraw("0x7b4bf9feccff207ef2cb7101ceb15b8516021acd");
    await rushBuy.contract.withdraw("0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c");
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
