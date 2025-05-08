import { ethers } from 'hardhat';
import { delay } from './util';

let previous = 0;
async function main() {
  const [deployer] = await ethers.getSigners();

  while (true) {
    
    const cur = await ethers.provider.getBlockNumber();
    if (cur !== previous) {
      console.log(cur);
      previous = cur;
    }

    await delay(500);
  }
}

main();
