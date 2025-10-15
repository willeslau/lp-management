import { ethers } from 'hardhat';
import { fromNetwork } from './config';

const pool = "0x172fcD41E0913e95784454622d1c3724f546f849";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await fromNetwork(deployer);

    const deadline = Math.floor(Date.now() / 1000) + 10;
    await lpManager.close(deadline);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
