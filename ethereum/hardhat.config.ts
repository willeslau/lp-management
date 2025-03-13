// require('hardhat-ethernal');
import "@nomicfoundation/hardhat-ethers";
import "@nomicfoundation/hardhat-toolbox";

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.12",
  networks: {
    hardhat: {
      chainId: 31337,
    },
    ethereum: {
      chainId: 1,
      // url: "https://mainnet.infura.io/v3/690f68e5f6a54dc1a47756167c97d058",
      url: "https://muddy-spring-patron.quiknode.pro/ed0f9bed6f68b622580b7110b03756d08108bf3b",
      accounts: [`${process.env.PRIVATE_KEY!}`],
    },
  },
  settings: {
    viaIR: true,
    optimizer: {
      enabled: true,
      runs: 200,
      details: {
        yulDetails: {
          optimizerSteps: "u",
        },
      },
    }
  }
};