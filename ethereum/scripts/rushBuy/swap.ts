import { ethers } from 'hardhat';
import { networkConfig } from './config';
import { delay, loadContract } from '../util';

const gasLimit = 481602;
const gasPrice = ethers.parseUnits("10", "gwei");

const params = {
  pool: "0x6ec31af1bb9a72aacec12e4ded508861b05f4503",
  tokenIn: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
  swap: {
    swapper: 0,
    zeroForOne: true,
    priceSqrtX96Limit: 7902984389905972504659943751680n,
    amountOutMin: ethers.parseEther("60000"),
    amountIn: ethers.parseEther("6"),
  }
};

async function main() {
  try {
    const [deployer] = await ethers.getSigners();
    console.log(`Call contract with account: ${deployer.address}`);

    const config = networkConfig();

    console.log(config.swapUtil);
    const contract = await loadContract('SwapUtil', config.swapUtil!, deployer);

    while (true) {
      await contract.swap(
        params.pool,
        params.tokenIn,
        params.swap,
        {
          gasLimit, gasPrice
        }
      );
      // break;
      await delay(1500);
    }
  
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
