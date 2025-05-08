import { Signer } from "ethers";
import { network } from "hardhat";
import { RushBuy } from "../RushBuy";

export interface NetworkConfig {
    rushBuy: string | undefined,
    swapUtil: string | undefined,
}

export const config: {[key: string]: NetworkConfig} = {
    bnb: {
        rushBuy: "0x6918DD7c1040580Fff338D3777B855e6788aEAcd",
        swapUtil: "0x5dE6A737F580235E1B81a54ca4eE32ce52802aeD",
    },
}

export async function rushBuyFromNetwork(caller: Signer): Promise<RushBuy> {
    const networkName = network.name;
    const c = config[networkName];
    return await RushBuy.fromConfig(caller, c.rushBuy!!);
}

export function networkConfig(): NetworkConfig {
    const networkName = network.name;
    return config[networkName];
}