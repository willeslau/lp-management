import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const positionKey = "0xe79a875d324957a5b2d64a4894094456536a579f3b8ec92c6e5beeac7a154739";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    console.log("position", await lpManager.getPosition(positionKey));
    console.log("fees", await lpManager.getPositionFees(positionKey));

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
