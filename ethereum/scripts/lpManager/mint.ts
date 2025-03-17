import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

const contractAddress = "0x6E3aC11F344BE1B91E433Cc543231187d8E30F99";
const tokenPairId = 1;
const token0 = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984";
const token1 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

const amount0 = ethers.parseEther("1");
const amount1 = ethers.parseEther("0.003339453501870503");

const tickLower = -57660n;
const tickUpper = -57060n;

const slippage = 0.99;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);

    await lpManager.useCaller(deployer);

    // await lpManager.increaseAllowanceIfNeeded(token0, amount0);
    // console.log("increase allowance for token 0");
    // await lpManager.increaseAllowanceIfNeeded(token1, amount1);
    // console.log("increase allowance for token 1");

    const params = lpManager.createMintParams(tickLower, tickUpper, amount0, amount1, slippage)
    const postionChange = await lpManager.mintNewPosition(
      tokenPairId,
      params
    );

    // {
    //     tokenPair: 1n,
    //     change: 0,
    //     amount0: 824440845254751502n,
    //     amount1: 3339453501870503n,
    //     positionKey: '0xef766d62d0a9eca567b5a68293ba0dc3c72bfabf8afbfeadca314f4dfeaaceed'
    //   }
    console.log(postionChange);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
