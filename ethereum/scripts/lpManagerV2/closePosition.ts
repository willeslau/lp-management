import { ethers } from 'hardhat';
import { lpManagerFromNetwork } from './config';

const vaultIds = [3];

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const lpManager = await lpManagerFromNetwork(deployer);
    await lpManager.useCaller(deployer);

    const [_, vaults] = await lpManager.listVaults(vaultIds);


    const promises = [];
    for (const vault of vaults) {
      console.log("vault", vault.vaultId);

      if (vault.position.liquidity === 0) {
        continue;
      }

      const params = {
        vaultId: vault.vaultId,
        tickLower: vault.position.tickLower,
        tickUpper: vault.position.tickUpper,
        amount0Min: 0n,
        amount1Min: 0n,
        compoundFee: true,
      };
      console.log(params);
      await lpManager.closeVaultPosition(params);
    }

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();
