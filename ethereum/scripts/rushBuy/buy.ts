import { ethers } from 'hardhat';
import { networkConfig, rushBuyFromNetwork } from './config';
import { delay } from '../util';

const params = {
  pool: "0x56EB1e376B46c874cE32aB0239Da93A15dBAf938",
  token0: "0x7b4bf9feccff207ef2cb7101ceb15b8516021acd",
  token1: "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c",
  decimal0: 18,
  deciaml1: 18,

  zeroForOne: false,
  maxSlippage: 0.5,
  lowerBound: 0.6,
  upperBound: 1.4,
};

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Deploying contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const rushBuy = await rushBuyFromNetwork(deployer);
    const buyParams = await rushBuy.createBuyParams(
      params.pool, 
      params.token0, 
      params.token1, 
      params.decimal0,
      params.deciaml1,
      params.zeroForOne,
      params.maxSlippage,
      params.lowerBound,
      params.upperBound,
    );
    buyParams.priceProtection = 80147209199429803909629060159897600000000000n;

    while (true) {
      try {
        await rushBuy.buy(buyParams);
      } catch(e) {
        console.log(e);
      }
      
      await delay(1500);
    }
  
    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
