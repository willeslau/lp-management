import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';
import { lpManagerFromNetwork } from './config';

const contractAddress = "0x6E3aC11F344BE1B91E433Cc543231187d8E30F99";
const tokenPairId = 1;

const amount0 = ethers.parseEther("0.824440");
const amount1 = ethers.parseEther("0.00333945");

const sqrtPriceLimitX96 = 4645668578301454086026821632n;
const tickLower = -58320n;
const tickUpper = -56340n;

const R_Q96 = 269460230623460860335489024n;

const searchRange = {
  swapInLow: ethers.parseEther("0.000262614"),
  swapInHigh: ethers.parseEther("0.00026524"),
  searchLoopNum: 8,
};

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);

    await lpManager.useCaller(deployer);

    // now, off chain calculation based on current liquidity and price sqrt
    const rebalanceParams = {
        tokenPairId,
        sqrtPriceLimitX96,
        maxMintSlippageRate: lpManager.toOnChainRate(0.03),
        tickLower,
        tickUpper,
        R_Q96,
        amount0,
        amount1,
        searchRange,
    }

    // await lpManager.useCaller(deployer);

    // const positionChange = await lpManager.rebalance1For0(rebalanceParams);

    console.log(
      lpManager.innerContract.interface.getError("19a2cf76")
    );
    // console.log(positionChange);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
