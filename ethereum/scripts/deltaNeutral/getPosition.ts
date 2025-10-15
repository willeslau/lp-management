import { ethers } from 'hardhat';
import { fromNetwork } from './config';
import JSBI from 'jsbi';
async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const operator = await fromNetwork(deployer);
    // console.log(await operator.getPosition());

    console.log(await operator.estimateCakeAPR(
      50960,
      51050,
      JSBI.BigInt(0),
      JSBI.BigInt(19),
      360,
      0.75
    ));
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
