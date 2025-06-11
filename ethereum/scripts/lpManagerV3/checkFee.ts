import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';
import { delay } from '../util';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const tickLower = -65105;
const tickUpper = -65091;

const amount0 = ethers.parseEther("1000");
const amount1 = ethers.parseEther("10");
const decimals0 = 18;
const decimals1 = 18;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);

    while(true) {
      // const feeGrowthNow = await lpManager.getFeeGrowthNow(pool, tickLower, tickUpper);
      // const feeGrowthWindow = await lpManager.getFeeGrowth(pool, liquidity, tickLower, tickUpper, 60, 1.5);

      const estimatedApr = await lpManager.estimateAPR(pool, amount0, amount1, tickLower, tickUpper, 100, 1.5, decimals0, decimals1);
      console.log(estimatedApr);
      await delay(3000);
    }


    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
