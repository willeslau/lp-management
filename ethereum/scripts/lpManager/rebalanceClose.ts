import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

const contractAddress = "0x6E3aC11F344BE1B91E433Cc543231187d8E30F99";
const positionKey = "0xef766d62d0a9eca567b5a68293ba0dc3c72bfabf8afbfeadca314f4dfeaaceed";

const amount0 = ethers.parseEther("0.8");
const amount1 = ethers.parseEther("0.003");

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);

    await lpManager.useCaller(deployer);

    const params = {
        amount0Min: amount0,
        amount1Min: amount1,
        compoundFee: true
    };

    const positionChange = await lpManager.rebalanceClosePosition(positionKey, params);
    console.log(positionChange);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
