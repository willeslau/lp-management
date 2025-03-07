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