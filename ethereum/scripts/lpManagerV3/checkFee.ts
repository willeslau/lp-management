import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';
import { delay } from '../util';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const tickLower = -65250;
const tickUpper = -65221;
const liquidity = 264334356510589449931417n;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);

    while(true) {
      // const feeGrowthNow = await lpManager.getFeeGrowthNow(pool, tickLower, tickUpper);
      const feeGrowthWindow = await lpManager.getFeeGrowth(pool, liquidity, tickLower, tickUpper, 60, 1.5);
      console.log(
        Number(feeGrowthWindow[0]) / Number(ethers.parseEther("1")),
        Number(feeGrowthWindow[1]) / Number(ethers.parseEther("1")),
      );
      await delay(3000);
    }


    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
