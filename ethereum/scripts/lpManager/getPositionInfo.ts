import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

const positionKey = "0x1e109bde0211e4fe9880a82fa2b5a14eb76e0fdc23022e8b722c2135b6b49384";

const contractAddress = "0x6E3aC11F344BE1B91E433Cc543231187d8E30F99";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);
    console.log(await lpManager.getPosition(positionKey));

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
