import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

const contractAddress = "0xA7Fc9aA1a78c2560611A968A44473c9872093b98";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);

    const result = await lpManager.listPositionKeys(0, 0);
    console.log(result);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
