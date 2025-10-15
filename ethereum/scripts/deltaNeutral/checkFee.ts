import { ethers } from 'hardhat';
import { fromNetwork } from './config';
import { delay } from '../util';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";
const tickLower = -64957;
const tickUpper = -65061;

const decimals0 = 18;
const decimals1 = 18;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const operator = await fromNetwork(deployer);

    while(true) {
      const estimatedApr = await operator.estimateAPR(tickLower, tickUpper, 100, 1.5, decimals0, decimals1);
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
