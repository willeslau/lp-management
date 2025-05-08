import { ethers } from 'hardhat';
import { loadContract } from '../util';

// eth
// const contractAddress = "0xBD05497f929013375da90768e1253bD03762a903";

// bnb
const contractAddress = "0x74D44D29b1Ba2989C0f3371DECDc419A86296f34";

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3TokenPairs', contractAddress, deployer);
    const tokenPairs = await contract.getAllTokenPairs();

    for (const p of tokenPairs) {
      const uniswapV3 = await loadContract('UniswapV3Pool', p.pool, deployer);
      const tickSpacing = await uniswapV3.tickSpacing();

      const token0 = await loadContract("ERC20", p.token0, deployer);
      const decimal0 = await token0.decimals();

      const token1 = await loadContract("ERC20", p.token1, deployer);
      const decimal1 = await token1.decimals();

      console.log(`${p.id}:`);
      console.log(`  address: "${p.pool}"`);
      console.log(`  decimals: [${decimal0}, ${decimal0}]`);
      console.log(`  tick_spacing: ${tickSpacing}`);
    }

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
