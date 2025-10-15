import { Signer } from "ethers";
import { network } from "hardhat";
import { DeltaNeutral, DeployContractParams } from "../DeltaNeutral";

export interface NetworkConfig {
    addresses: {
        lpOperator: string | undefined,
        uniswapPool: string
    },
    deployment: DeployContractParams
}

export const config: {[key: string]: NetworkConfig} = {
    bnb: {
        addresses: {
            lpOperator: "0xCAAa83e5Bb1B1361b788c75148fa0Dc24D7Ef636",
            uniswapPool: "0x6bbc40579ad1BBD243895cA0ACB086BB6300d636",
        },
        deployment: {
            swapMath: "0x1Df0488d307aa38e911E34C341Fd786deC184E17",
            swapUtil: "0x539D51f4b43Acf40C9897252146aDa28E8fC048B",
            nonfungiblePositionMananger: "0x46A15B0b27311cedF172AB29E4f4766fbE7F4364",
        }
    },
}

export async function fromNetwork(caller: Signer): Promise<DeltaNeutral> {
    const networkName = network.name;
    const c = config[networkName];
    return await DeltaNeutral.fromPool(network.config.chainId!, c.addresses.uniswapPool, c.addresses.lpOperator!, caller);
}

export function networkConfig(): NetworkConfig {
    const networkName = network.name;
    return config[networkName];
}