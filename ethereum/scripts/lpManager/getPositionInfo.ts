import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const positionKey = "0xf8a64a4c6f939f855cee9f7255935a259c392943d903e680dc09d631824ab9f3";

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
    const position = await lpManager.getPosition(positionKey);
    const feeToCollect = await lpManager.getPositionFees(positionKey);
    const reservesWithEarnings = await lpManager.getReservesWithEarnings(position.tokenPairId);

    const decimals = await lpManager.decimals(position.tokenPairId);
    const names = await lpManager.names(position.tokenPairId);

    const totalAmount0 = feeToCollect[0] + position.amount0 + reservesWithEarnings.reserves.amount0;
    const totalAmount1 = feeToCollect[1] + position.amount1 + reservesWithEarnings.reserves.amount1;

    console.log("position summary");
    console.log(`  ${names[0]} amount:`, toWei(position.amount0, decimals[0]));
    console.log(`  ${names[1]} amount:`, toWei(position.amount1, decimals[1]));
    console.log(`  ${names[0]} reserve:`, toWei(reservesWithEarnings.reserves.amount0, decimals[0]));
    console.log(`  ${names[1]} reserve:`, toWei(reservesWithEarnings.reserves.amount1, decimals[1]));
    // console.log("  amount in token 1: ", );
    console.log(`  ${names[0]} fee: `, toWei(feeToCollect[0], decimals[0]));
    console.log(`  ${names[1]} fee: `, toWei(feeToCollect[1], decimals[1]));
    // console.log("  fee in token 1: ", );
    console.log("  ===== CURRENT TOTAL HOLDING ===== ")
    console.log(`  ${names[0]} total: `, toWei(totalAmount0, decimals[0]));
    console.log(`  ${names[1]} total: `, toWei(totalAmount1, decimals[1]));
    console.log("  ===== TOTAL HISTORICAL =====")
    console.log(`  ${names[0]} total: `, toWei(totalAmount0 + reservesWithEarnings.fee.amount0, decimals[0]));
    console.log(`  ${names[1]} total: `, toWei(totalAmount1 + reservesWithEarnings.fee.amount1, decimals[1]));


    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
