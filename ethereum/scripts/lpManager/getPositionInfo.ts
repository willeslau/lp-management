import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

// eth
// const contractAddress = "0xCf38bE613203B39a14D2Fb3c1A345122ec0a4351";
// const positionKey = "0x6a088a1318528dc79f2c4c0b40a2c2113679ae5bcc2deed489183fa11b5a1233";

// bnb
const contractAddress = "0x502b5D6702a4E24C4f4D8A236aFC4CFA0cE40B5E";
const positionKey = "0x6a088a1318528dc79f2c4c0b40a2c2113679ae5bcc2deed489183fa11b5a1233";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);
    console.log("position", await lpManager.getPosition(positionKey));
    console.log("fees", await lpManager.getPositionFees(positionKey));

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
