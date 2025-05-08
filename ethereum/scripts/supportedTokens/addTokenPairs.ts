import { ethers } from "hardhat";
import { loadContract } from "../util";
import { assert } from "chai";

const endpoint = 'https://thegraph.com/explorer/api/playground/QmY67iZDTsTdpWXSCotpVPYankwnyHXNT7N95YEn8ccUsn';
const supportedTokenPair = "0x74D44D29b1Ba2989C0f3371DECDc419A86296f34";
const pools = [
  // { address: "0x673516e510d702ab5f2bbf0c6b545111a85f7ea7", token0Symbol: "ADA", token1Symbol: "WBNB"},
  // { address: "0xafb2da14056725e3ba3a30dd846b6bbbd7886c56", token0Symbol: "Cake", token1Symbol: "WBNB"},
  // { address: "0x7eb6b5ab4a075071e339e09d4f665a91b6007745", token0Symbol: "Raca", token1Symbol: "WBNB"},
  // { address: "0x0e1893beeb4d0913d26b9614b18aea29c56d94b9", token0Symbol: "WBNB", token1Symbol: "Link"},
  { address: "0x56EB1e376B46c874cE32aB0239Da93A15dBAf938", token0Symbol: "Milk", token1Symbol: "WBNB"},
];

type Token = {
  symbol: string;
  id: string;
  decimals: string;
};

type Pool = {
  tick: string;
  feeTier: string;
  sqrtPrice: string;
  liquidity: string;
  token0: Token;
  token1: Token;
};

type PoolResponse = {
  data: {
    pool: Pool | null;
  };
  errors?: { message: string }[];
};



async function fetchData(poolId: string): Promise<Pool> {
  const query = `{
    pool(id: "${poolId}") {
      tick
      token0 {
        symbol
        id
        decimals
      }
      token1 {
        symbol
        id
        decimals
      }
      feeTier
      sqrtPrice
      liquidity
    }
  }`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({query}),
  });

  const result: PoolResponse = await response.json();

  if (result.errors) {
    throw new Error(`GraphQL Error: ${result.errors.map(e => e.message).join(", ")}`);
  }

  const pool = result.data.pool;
  if (!pool) throw new Error("Pool not found.");

  return pool;
}

async function main() {
  try {
    const [deployer] = await ethers.getSigners();

    console.log(`Call contracts with account: ${deployer.address}`);

    const balance = await ethers.provider.getBalance(await deployer.getAddress());
    console.log(`Account balance: ${balance.toString()}`);

    const contract = await loadContract('UniswapV3TokenPairs', supportedTokenPair, deployer);

    const poolData = [];
    for (const p of pools) {
      console.log(`checking pool ${p.address}`);
      const pool = await fetchData(p.address.toLowerCase());

      assert(pool.token0.symbol.toLowerCase() === p.token0Symbol.toLowerCase(), `token0 not equal: ${pool.token0.symbol.toLowerCase()} vs ${p.token0Symbol.toLowerCase()}`);
      assert(pool.token1.symbol.toLowerCase() === p.token1Symbol.toLowerCase(), `token1 not equal: ${pool.token1.symbol.toLowerCase()} vs ${p.token1Symbol.toLowerCase()}`);

      poolData.push({address: p.address, token0: pool.token0.id, token1: pool.token1.id, fee: pool.feeTier});
    }

    console.log(`processing pools: ${JSON.stringify(poolData)}`);

    // for (const p of poolData) {
    //   const { address, token0, token1, fee } = p;
    //   const tx = await contract.addTokenPair(
    //     address,
    //     token0,
    //     token1,
    //     fee
    //   );
    //   await tx.wait();

    //   console.log(`added ${address} to ${supportedTokenPair}`);
    // }

    process.exit(0);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
}

main();