import { ethers } from 'hardhat';
import { loadContract } from '../util';

// const contractAddress = "0xCf83eb58B4f229224BD971bc2091B0eE868638C0";
const contractAddress = "0xAcA5Fa305273BAEe98f07b50F266e875B12b144E";
// token 1 is eth, token 0 is uniswap
const tokenIn = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const uniswapV3Pool = "0x1d42064fc4beb5f8aaf85f4617ae8b3b5b8bd801";

const zeroForOne = false;
const amount0 = ethers.parseEther("0");
const amount1 = ethers.parseEther("0.01");

const swapInLow = ethers.parseEther("0.0066");
const swapInHigh = ethers.parseEther("0.0071");
const R_Q96 = "122853940743367269558517760";
const sqrtPriceLimitX96 = "4565208564198453629868310528";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    // const token = await loadContract("IERC20", tokenIn, deployer);
    // await token.approve(contractAddress, ethers.parseEther("100000000000"));

    const contract = await loadContract("LiquiditySwapV3Debug", contractAddress, deployer);
    
    // const bytes = await contract.encodePreSwapData(
    //   zeroForOne,
    //     {
    //         amount0,
    //         amount1,
    //         R_Q96,
    //         tokenIn,
    //     }
    // );

    const bytes = "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002386f26fc10000000000000000000000000000000000000000000000659f5578fd81d000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
    
    // console.log("swap calldata", bytes.toString("hex"));

    // await contract.justSwap(
    //   uniswapV3Pool,
    //   sqrtPriceLimitX96,
    //   ethers.parseEther("0.001"),
    //   // {
    //   //     swapInLow,
    //   //     swapInHigh,
    //   //     searchLoopNum: 0,
    //   // },
    //   bytes,
    // );
    const logs = [
      "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000017cda1936385ba0000000000000000000000000000000000000000000000000017cd9d4ffec0000000000000000000000000000000000000000000000000000017cda1936385b9",
      "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000017cd9f71b122dc0000000000000000000000000000000000000000000000000017cd9d4ffec0000000000000000000000000000000000000000000000000000017cd9f71b122db",
    ];
    for (const l of logs) {
      const t = contract.interface.decodeEventLog("RevertCatch", l);
      console.log(t);
    }


    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
