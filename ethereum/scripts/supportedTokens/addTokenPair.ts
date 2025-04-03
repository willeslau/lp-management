import { ethers } from 'hardhat';
import { loadContract } from '../util';

// eth
// const contractAddress = "0xBD05497f929013375da90768e1253bD03762a903";
// const token0 = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984";
// const token1 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
// const poolAddress = "0x1d42064fc4beb5f8aaf85f4617ae8b3b5b8bd801";
// const fee = "3000";

// bnb
const contractAddress = "0x8cCFd5AdE5F217E29f91a0C81B2A7371a3B7fbB2";

// // id = 1
// const token0 = "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d";
// const token1 = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c";
// const poolAddress = "0xf2688fb5b81049dfb7703ada5e770543770612c4";
// const fee = "100";

// // id = 2
// const token0 = "0x55d398326f99059ff775485246999027b3197955";
// const token1 = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c";
// const poolAddress = "0x172fcd41e0913e95784454622d1c3724f546f849";
// const fee = "100";

// // id = 3, pepe/bnb (ts = 200)
// const token0 = "0x25d887ce7a35172c62febfd67a1856f20faebb00";
// const token1 = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c";
// const poolAddress = "0xdD82975ab85E745c84e497FD75ba409Ec02d4739";
// const fee = "10000";

// // id = 4, xrp/usdt (ts = 50)
// const token0 = "0x1d2f0da169ceb9fc7b3144628db156f3f6c60dbe";
// const token1 = "0x55d398326f99059ff775485246999027b3197955";
// const poolAddress = "0x71f5a8F7d448E59B1ede00A19fE59e05d125E742";
// const fee = "2500";

// id = 5, kilo/bnb (ts = 200)
const token0 = "0x503fa24b7972677f00c4618e5fbe237780c1df53";
const token1 = "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c";
const poolAddress = "0xd3BC30079210bEF8a1f9C7C21e3C5BecCfC1DfCb";
const fee = "10000";

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
