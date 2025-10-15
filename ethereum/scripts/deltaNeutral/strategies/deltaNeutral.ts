import { ethers } from 'hardhat';
import { fromNetwork } from '../config';
import { DeltaNeutral } from '../../DeltaNeutral';
import { delay } from '../../util';
import { obtainRange } from "./analysis";
import JSBI from 'jsbi';

const deltaNeutralConfig = {
  token1Exposure: 200,
  breakEvenDurationSeconds: 1800,
  slippage: JSBI.BigInt(100), // 1%
};

// TODOs: 
// 1. fee estimation on pancake is not accurate
// 2. the exit strategy

// Detection logic:
// In the next X (PARAMETER_1) minutes:
//  Step 1: Estimate volatility (ESTIMATION 1)
//  Step 2: Estimate price increase given the volatility, estimate the loss (ESTIMATION_2), go to Step 3.
//  Step 3: Estimate the fee earning X minutes (ESTIMATIOIN_3), go to Step 5.
//          If ESTIMATION_2 > ESTIMATION_3 * EARN_BUFFER (PARAMETER_2), go to Step 1
//          Else CREEATE_POSITION

// Analysis:
// The issue with delta neutral is that if the range is too small, it will rebalance too early and materalizes the IL.
// When the price is out of range, we should give it some buffer time or wait time.
async function obtainOperator(): Promise<DeltaNeutral> {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    return await fromNetwork(deployer);
}

function weiToEther(wei: BigInt | Number): number {
  return Number(wei) / Math.pow(10, 18)
}

async function runLoop(operator: DeltaNeutral): Promise<void> {
    const hasPosition = await operator.hasPosition();

    if (hasPosition) {
      const position = await operator.getPosition();
      const [open1, current1, token1Delta] = await operator.tokenAmountDeltaFromPosition(position);

      if (Math.abs(token1Delta) <= deltaNeutralConfig.token1Exposure) {
        const monitor = await operator.getPositionFees();
        console.log("position in range");
        console.log("   amounts: ", monitor.principle.token0, monitor.principle.token1);
        console.log("   fees: ", weiToEther(monitor.fees[0]), weiToEther(monitor.fees[1]));
        console.log(`   open token1 ${weiToEther(open1)}, current token1: ${weiToEther(current1)}, token 1 delta: ${token1Delta}`);
        return;
      }

      console.log("delta neutral condition breached, current", token1Delta, "target", deltaNeutralConfig.token1Exposure);
      await operator.close();

      console.log("closed position");
    }

    console.log("no position at the moment, ready to open position");

    const derivedRange = await obtainRange();
    if (derivedRange === undefined) {
      return;
    }

    const [tickLower, tickUpper] = await operator.deriveTickRange(derivedRange);
    const feeRate = await operator.estimateAPR(tickLower, tickUpper, 360, 0.75);

    if (feeRate < 200) {
      console.log("fee rate less than 200%", feeRate, tickLower, tickUpper);
      return;
    }

    // const [principleUSDT, loss] = await operator.estimateLoss(tickLower, tickUpper, deltaNeutralConfig.slippage, deltaNeutralConfig.token1Exposure);

    // const breakEvenDurationSeconds = loss * (100 * 365 * 24 * 3600) / principleUSDT;
    // if (breakEvenDurationSeconds > deltaNeutralConfig.breakEvenDurationSeconds) {
    //   console.log("fee rate more than loss range, estimated fee apr", feeRate, "break even seconds", breakEvenDurationSeconds);
    //   return;
    // }

    console.log("create range", derivedRange, "ticks:", tickLower, tickUpper, "estimated fee apr", feeRate);

    // // 5810
    // const newQuote = await operator.quotePool(tickLower, tickUpper, deltaNeutralConfig.slippage);
    // const mint = await operator.swapAndMint(newQuote[0], tickLower, tickUpper);
    // console.log("position minted", mint);
}

async function main() {
  const operator = await obtainOperator();

  while(true) {
    try {
      await runLoop(operator);
    } catch (e) {
      console.log("encountered error", e);
    }

    await delay(5000);
  }
  
}

main();

// -65357n top
// num bnb: 14.533
// num usdt: 9965.063
