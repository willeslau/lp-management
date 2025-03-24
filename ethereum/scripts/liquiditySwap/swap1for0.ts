import { ethers } from 'hardhat';
import { loadContract } from '../util';

const contractAddress = "0x64605ADfd673EB59d75Ee9106BBD9F13432cfED3";

// token 1 is eth, token 0 is uniswap
const tokenIn = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const uniswapV3Pool = "0x1d42064fc4beb5f8aaf85f4617ae8b3b5b8bd801";

const zeroForOne = false;
const amount0 = ethers.parseEther("0");
const amount1 = ethers.parseEther("0.01");

const swapInLow = ethers.parseEther("0.00671");
const swapInHigh = ethers.parseEther("0.0068");
const R_Q96 = "121694795424088801216036864";
const sqrtPriceLimitX96 = "4569840734580474541399605248";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    // const token = await loadContract("IERC20", tokenIn, deployer);
    // await token.approve(contractAddress, ethers.parseEther("0.01"));

    const contract = await loadContract("LiquiditySwapV3", contractAddress, deployer);
    
    const bytes = await contract.encodePreSwapData(
      zeroForOne,
        {
            amount0,
            amount1,
            R_Q96,
            tokenIn,
        }
    );

    console.log("swap calldata", bytes.toString("hex"));

    
    await contract.swapWithSearch1For0(
      uniswapV3Pool,
      sqrtPriceLimitX96,
      {
          swapInLow,
          swapInHigh,
          searchLoopNum: 15,
      },
      bytes,
      // {
      //   gasLimit: 292880
      // }
    );

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
