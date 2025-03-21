import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

// eth
// const contractAddress = "0xCf38bE613203B39a14D2Fb3c1A345122ec0a4351";

// bnb
const contractAddress = "0x502b5D6702a4E24C4f4D8A236aFC4CFA0cE40B5E";
async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);
    console.log(await lpManager.listPositionKeys(0, 1000));

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
