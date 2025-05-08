import { Signer } from "ethers";
import { LPManagerV2 } from "../LPManagerV2";
import { network } from "hardhat";

export interface NetworkConfig {
    lpManager: string | undefined,
    uniswapUtil: string | undefined,
    swapUtil: string | undefined,
    supportedTokenPair: string | undefined,
}

export const config: {[key: string]: NetworkConfig} = {
    bnb: {
        // lpManager: "0x9D6b45F5707f7B2Bc6Ce41EcB19a43FaACdFF8A2",
        lpManager: "0xf48AE171c2a116b39bC2F5247a771c975158E001",
        uniswapUtil: "0xb5B1e05EE104D620991836493690324d5f6F1d30",
        supportedTokenPair: "0x74D44D29b1Ba2989C0f3371DECDc419A86296f34",
        swapUtil: "0x5dE6A737F580235E1B81a54ca4eE32ce52802aeD",
    },
}

export async function lpManagerFromNetwork(caller: Signer): Promise<LPManagerV2> {
    const networkName = network.name;
    const c = config[networkName];
    return await LPManagerV2.fromConfig(caller, c.lpManager!, c.uniswapUtil!);
}

export function networkConfig(): NetworkConfig {
    const networkName = network.name;
    return config[networkName];
}