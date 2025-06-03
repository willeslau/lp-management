import { Signer } from "ethers";
import { LPManagerV3 } from "../LPManagerV3";
import { network } from "hardhat";

export interface NetworkConfig {
    lpManager: string | undefined,
    uniswapUtil: string | undefined,
}

export const config: {[key: string]: NetworkConfig} = {
    bnb: {
        lpManager: "0xc8E8bDC1Aa18a868A7f47De6a7cD72749cc54595",
        uniswapUtil: "0xcAdccE8D4329819954e384503f6Db3b4c23A135C",
    },
}

export async function lpManagerFromNetwork(caller: Signer): Promise<LPManagerV3> {
    const networkName = network.name;
    const c = config[networkName];
    return await LPManagerV3.fromConfig(caller, c.lpManager!, c.uniswapUtil!);
}

export function networkConfig(): NetworkConfig {
    const networkName = network.name;
    return config[networkName];
}