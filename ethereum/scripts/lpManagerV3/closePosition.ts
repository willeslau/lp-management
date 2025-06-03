import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.useCaller(deployer);

    await lpManager.closePosition(pool);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
