import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

export const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";

const range = 0.0003;

// TODOs: 
// 1. tick spacing not considered
// 2. the range is not accurate
// 3. fee estimation on pancake is not accurate
// 4. the exit strategy

// Detection logic:
// In the next X (PARAMETER_1) minutes:
//  Step 1: Estimate volatility (ESTIMATION 1)
//  Step 2: Estimate price increase given the volatility, estimate the loss (ESTIMATION_2), go to Step 3.
//  Step 3: Estimate the fee earning X minutes (ESTIMATIOIN_3), go to Step 5.
//          If ESTIMATION_2 > ESTIMATION_3 * EARN_BUFFER (PARAMETER_2), go to Step 1
//          Else ENTER

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.rebalance(pool, range);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();

// -65357n top
// num bnb: 14.533
// num usdt: 9965.063
