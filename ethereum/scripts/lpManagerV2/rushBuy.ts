import { artifacts, ethers } from 'hardhat';
import { networkConfig, lpManagerFromNetwork } from './config';
import { Swapper } from '../LPManagerV2';

const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms))

const buyConfig = {
  poolAddress: "0x6e8f6068c312dab9c1f62530959d801ed16b64be",
  startBlock: 48750599,
  amount0Min: ethers.parseEther("10000000"),
  rebalance: {
    vaultId: 4,
    swap: {
      swapper: Swapper.UniswapPool,
      zeroForOne: false,
      priceSqrtX96Limit: 19406857141824917686794059776n,
      amountOutMin: ethers.parseEther("330000"),
      amountIn: ethers.parseEther("33"),
    },
    mint: {
      tickLower: -97500,
      tickUpper: -91520,
      amount0Min: 0n,
      amount1Min: 0n
    }
  }
}

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Buy with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const artifact = await artifacts.readArtifact("UniswapV3Pool");
    const iface = new ethers.Interface(artifact.abi);
    const eventTopic = iface.getEvent("Mint")!.topicHash;

    const lpManager = await lpManagerFromNetwork(deployer);

    const scanLimit = 1;
    let startBlock = buyConfig.startBlock;

    // while (true) {
    //   const latestBlockHeader = await ethers.provider.getBlock("latest", false);
    //   const latest = latestBlockHeader!.number;

    //   let end = Math.min(scanLimit + startBlock, latest);

    //   if (startBlock >= end) {
    //     console.log("at head sleep");
    //     await delay(1500);
    //     continue;
    //   }
    //   console.log("scanned", startBlock, end, buyConfig.poolAddress, eventTopic);

    //   const logs = await ethers.provider.getLogs({
    //     address: buyConfig.poolAddress,
    //     fromBlock: startBlock,
    //     toBlock: end,
    //     topics: [eventTopic],
    //   });

    //   startBlock = end + 1;

    //   if (logs.length === 0) {
    //     continue;
    //   }

    //   let isBuy = true;
    //   for (const log of logs) {
    //     try {
    //       const parsed = iface.parseLog(log);
          
    //       const amount0 = parsed?.args.amount0;
    //       const amount1 = parsed?.args.amount1;

    //       console.log(amount0, amount1);

    //       if (amount0 > buyConfig.amount0Min) {
    //         isBuy = true;
    //         break;
    //       } else {
    //         console.log("amount 0 not enough");
    //       }
    //     } catch (e) {
    //     }
    //   }

    //   if (isBuy) {
    //     break;
    //   }
    // }

    while (true) {
      try {
        await lpManager.rebalance(buyConfig.rebalance);
        break;
      } catch(e) {
        console.log(e);
        continue;
      }
    }


    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
