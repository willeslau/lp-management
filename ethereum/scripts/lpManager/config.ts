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
        lpManager: "0x5e04A9c89a69BedeC316f349e2E69d1F4595Df20",
        uniswapUtil: "0xAccE28844FAA59A0b748A43f7Fc30a93A88e2fc7",
        supportedTokenPair: "0x3E4e0ABBd4cE2eeCA45a5ECd2F9fb3F38f1fF60F",
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