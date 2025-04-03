import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const tokenPairId = 4;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.useCaller(deployer);
    
    console.log(await lpManager.getReservesWithEarnings(tokenPairId));

    const positions = await lpManager.listPositionKeys(0, 100);
    for (const key of positions.positionKeys) {
      const fee = await lpManager.getPositionFees(key);
      console.log(`position ${key} fee to collect ${fee}`, );
    }

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
