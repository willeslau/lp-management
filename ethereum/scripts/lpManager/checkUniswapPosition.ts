import { ethers } from 'hardhat';
import { loadContract } from '../util';
import { solidityPackedKeccak256 } from 'ethers';

const contractAddress = "0x1d42064fc4beb5f8aaf85f4617ae8b3b5b8bd801";
const owner = "0xA7Fc9aA1a78c2560611A968A44473c9872093b98";
const tickLower = -57720;
const tickUpper = -54600;

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    const uniswapKey = solidityPackedKeccak256(
      ["address", "int24", "int24"], 
      [owner, tickLower, tickUpper]
    );
    console.log(uniswapKey);
    
    const contract = await loadContract('IUniswapV3Pool', contractAddress, deployer);
    console.log(await contract.positions(uniswapKey));
    console.log(await contract.slot0());

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
