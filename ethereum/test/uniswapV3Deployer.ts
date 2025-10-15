import { Contract, Signer } from "ethers";
import { deployContractWithDeployer, loadContract } from "../scripts/util";

export interface UniswapPool {
    factory: Contract,
    fee: number,
    pool: Contract,
    token0: string,
    token1: string,
    tickSpacing: BigInt,
}

export async function deployUniswapFactory(deployer: Signer, token0: string, token1: string, fee: number, initialPriceSqrtQ96: BigInt): Promise<UniswapPool> {
    const factory = await deployContractWithDeployer(deployer, "UniswapV3Factory", [], true);
    const tx = await factory.createPool(token0, token1, fee);
    const receipt = await tx.wait();

    let data = {
        factory,
        token0: "",
        token1: "",
        tickSpacing: BigInt(0),
        // placeholder
        pool: factory,
        fee,
    };

    let pool = "";
    receipt.logs.forEach(log => {
        try {
          // Attempt to parse the log using the contract's interface
          const parsedLog = factory.interface.parseLog(log)!;

          if (parsedLog.name === "PoolCreated") {
            data.token0 = parsedLog.args[0];
            data.token1 = parsedLog.args[1];
            data.tickSpacing = parsedLog.args[3];
            pool = parsedLog.args[4];
          } else {
            throw "No other errors possible";
          }

        } catch (error) {
          // The log might not belong to this contract, so skip it
        }
      });

    data.pool = await loadContract('IUniswapV3Pool', pool, deployer);

    await (await data.pool.initialize(initialPriceSqrtQ96)).wait();
    
    return data;
}