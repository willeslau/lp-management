// require('hardhat-ethernal');
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-contract-sizer";

// load .env config
const dotenvConfig = require("dotenv").config;
import { resolve } from "path";

dotenvConfig({ path: resolve(__dirname, "./.env") });

const { PRIVATE_KEY } = process.env;

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

let config = {
  solidity: {
    compilers: [
      {
        version: "0.8.12",
        settings: {
          viaIR: false,
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yulDetails: {
                optimizerSteps: "u",
              },
            },
          },
        },
      },
      // {
      //   version: "0.8.15",
      //   settings: {
      //     viaIR: true,
      //     optimizer: {
      //       enabled: true,
      //       runs: 200,
      //       details: {
      //         yulDetails: {
      //           optimizerSteps: "u",
      //         },
      //       },
      //     },
      //   },
      // },
    ],
  },
  networks: {
    hardhat: {
      chainId: 31337,
      allowUnlimitedContractSize: true
    },
    ethereum: {
      chainId: 1,
      // url: "https://mainnet.infura.io/v3/690f68e5f6a54dc1a47756167c97d058",
      url: "https://muddy-spring-patron.quiknode.pro/ed0f9bed6f68b622580b7110b03756d08108bf3b",
      accounts: [`${PRIVATE_KEY}`],
    },
  },
  contractSizer: {
    alphaSort: true,
    disambiguatePaths: true,
    runOnCompile: true,
    strict: true,
    except: ["contracts/TestUtil", "contracts/mocks", "@uniswap/*", "@openzeppelin/*"],
  }
};

module.exports = config;
