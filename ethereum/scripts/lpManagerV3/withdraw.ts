import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const amount = ethers.parseEther("0");
const token = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);

        // const token0 = new Token(56, '0x55d398326f99059fF775485246999027B3197955', 18, 'USDT', 'USDT')
        // const token1 = new Token(56, '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c', 18, 'WBNB', 'Wrapped BNB')

    if (amount === BigInt(0)) {
      await lpManager.withdraw(token);
    } else {
      await lpManager.withdrawAmount(token, amount);
    }

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
