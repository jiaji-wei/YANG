import { task } from "hardhat/config";
import 'hardhat-typechain'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (args, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const DEFAULT_COMPILER_SETTINGS = {
  version: '0.7.6',
  settings: {
    optimizer: {
      enabled: true,
      runs: 2000,
    },
    metadata: {
      bytecodeHash: 'none',
    },
  },
}

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    mainnet: {
      url: `${process.env.MAINNET_API_URL}`,
    },
    kovan: {
      url: `${process.env.KOVAN_API_URL}`,
    },
  },
  etherscan: {
    // For verify contract
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  solidity: {
    compilers: [DEFAULT_COMPILER_SETTINGS],
  },
};
