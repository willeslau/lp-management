import { ethers } from 'hardhat';
import { loadContract } from '../util';

// eth
// const contractAddress = "0xBD05497f929013375da90768e1253bD03762a903";

// bnb
const contractAddress = "0x8cCFd5AdE5F217E29f91a0C81B2A7371a3B7fbB2";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3TokenPairs', contractAddress, deployer);
    console.log(await contract.getAllTokenPairs());

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
