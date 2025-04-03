import { Signer } from "ethers";
import { LPManager } from "../LPManager";
import { network } from "hardhat";

export interface NetworkConfig {
    lpManager: string | undefined,
    uniswapUtil: string | undefined,
    supportedTokenPair: string | undefined,
}

export const config: {[key: string]: NetworkConfig} = {
    bnb: {
        lpManager: "0x11a14e8bce0eb3ff03c225f05ca9679671e581e9",
        uniswapUtil: "0xAccE28844FAA59A0b748A43f7Fc30a93A88e2fc7",
        supportedTokenPair: "0x8cCFd5AdE5F217E29f91a0C81B2A7371a3B7fbB2"
    },
    ethereum: {
        lpManager: "0xCf38bE613203B39a14D2Fb3c1A345122ec0a4351",
        uniswapUtil: "0xCf38bE613203B39a14D2Fb3c1A345122ec0a4351",
        supportedTokenPair: "0xBD05497f929013375da90768e1253bD03762a903",
    }
}

export async function lpManagerFromNetwork(caller: Signer): Promise<LPManager> {
    const networkName = network.name;
    const c = config[networkName];
    return await LPManager.fromConfig(caller, c.lpManager!, c.uniswapUtil!);
}

export function networkConfig(): NetworkConfig {
    const networkName = network.name;
    return config[networkName];
}