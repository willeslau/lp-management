import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const positionKey = "0x332ee88de5e81accb179e47bc4ee60ec66be01b4cb75b0377620655196f16404";

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
        compoundFee: false
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
