import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const positionKey = "0xe79a875d324957a5b2d64a4894094456536a579f3b8ec92c6e5beeac7a154739";

const amount0 = ethers.parseEther("0");
const amount1 = ethers.parseEther("0");

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
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
