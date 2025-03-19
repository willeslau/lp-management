import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

const contractAddress = "0x6E3aC11F344BE1B91E433Cc543231187d8E30F99";
const tokenPairId = 1;

const amount0 = ethers.parseEther("0.824440");
const amount1 = ethers.parseEther("0.00333945");

const sqrtPriceLimitX96 = 4645668578301454086026821632n;
const tickLower = -58380n;
const tickUpper = -56340n;

const R_Q96 = 260863161557104411541504000n;

const searchRange = {
  swapInLow: ethers.parseEther("0.00026724"),
  swapInHigh: ethers.parseEther("0.00027073"),
  searchLoopNum: 15,
};

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    
    const r = contract.interface.getFunction("0xa5a1f2ec")!;
    console.log(contract.interface.decodeFunctionData(r, "0xa5a1f2ec000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000e309d3aae05290000000000000000000000000000000000000000000000000000000000000000000000001effffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1e88ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff2ab8000000000000000000000000000000000000000000000000167775d819536f090000000000000000000000000000000000000000000000000003124d4fb3efd900000000000000000000000000000000000000000028629b8939bafc000000000000000000000000000000000000000000000000000000000079c90f5cc38800000000000000000000000000000000000000000000000000007a45dc621eb000000000000000000000000000000000000000000000000000000000000000000a"));
    
    
    const lpManager = new LPManager(contract);

    // await lpManager.useCaller(deployer);

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

    // const positionChange = await lpManager.rebalance0For1(rebalanceParams);
    // console.log(positionChange);

    // console.log(
    //   await lpManager.getPosition("0x1e109bde0211e4fe9880a82fa2b5a14eb76e0fdc23022e8b722c2135b6b49384")
    // );

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
