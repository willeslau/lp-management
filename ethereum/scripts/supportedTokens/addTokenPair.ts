import { ethers } from 'hardhat';
import { loadContract } from '../util';

const contractAddress = "0xBD05497f929013375da90768e1253bD03762a903";
const token0 = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984";
const token1 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
const poolAddress = "0x1d42064fc4beb5f8aaf85f4617ae8b3b5b8bd801";
const fee = "3000";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3TokenPairs', contractAddress, deployer);
    const tx = await contract.addTokenPair(
      poolAddress,
      token0,
      token1,
      fee
    );
    await tx.wait();

    console.log(`added to ${await contractAddress}`);

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
