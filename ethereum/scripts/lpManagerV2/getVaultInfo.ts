import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const vaultIds = [4];

function toWei(amount: bigint, decimals: number): Number {
  return Number(amount) / Math.pow(10, Number(decimals));
}

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    const [_, vaults] = await lpManager.listVaults(vaultIds);

    for (const vault of vaults) {
      console.log("vault", vault.vaultId);
      console.log(" token pair id", vault.tokenPairId);
      console.log(` fee0 earned: ${toWei(vault.feeEarned.amount0, 18)}:`);
      console.log(` fee1 earned: ${toWei(vault.feeEarned.amount1, 18)}:`);
      console.log(` reserve0: ${toWei(vault.reserves.amount0, 18)}:`);
      console.log(` reserve1: ${toWei(vault.reserves.amount1, 18)}:`);

      if (vault.position.liquidity > 0) {
        console.log(` position:`);
        console.log(`   tickLower: ${vault.position.tickLower}`);
        console.log(`   tickUpper: ${vault.position.tickUpper}`);
        console.log(`   liquidity: ${vault.position.liquidity}`);
      }
    }
    // const feeToCollect = await lpManager.getPositionFees(positionKey);
    // const reservesWithEarnings = await lpManager.getReservesWithEarnings(position.tokenPairId);

    // const decimals = await lpManager.decimals(position.tokenPairId);
    // const names = await lpManager.names(position.tokenPairId);

    // const totalAmount0 = feeToCollect[0] + position.amount0 + reservesWithEarnings.reserves.amount0;
    // const totalAmount1 = feeToCollect[1] + position.amount1 + reservesWithEarnings.reserves.amount1;

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
