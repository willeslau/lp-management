import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { LPManager } from '../LPManager';

const contractAddress = "0xA7Fc9aA1a78c2560611A968A44473c9872093b98";
const positionKey = "0x868104b0bc6baf84a4322c1c568ba5195a82dd65a87742667731333656da8f10";

const amount0 = ethers.parseEther("0");
const amount1 = ethers.parseEther("0");

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3LpManager', contractAddress, deployer);
    const lpManager = new LPManager(contract);

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
