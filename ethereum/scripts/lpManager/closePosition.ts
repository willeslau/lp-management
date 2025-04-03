import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const positionKey = "0xd7c945481c816376cdb06ea65dc9a30f647b9b933398804facc65efc778dffc8";

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

    const positionChange = await lpManager.closePosition(positionKey, amount0, amount1);
    console.log(positionChange);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
