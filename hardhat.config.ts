import '@typechain/hardhat'
import '@nomiclabs/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import '@nomiclabs/hardhat-etherscan'
import 'hardhat-contract-sizer'
import 'hardhat-abi-exporter';
import "@nomiclabs/hardhat-etherscan";

import { task, HardhatUserConfig } from 'hardhat/config'

task("accounts", "Prints the list of accounts", async (args, hre) => {
    const accounts = await hre.ethers.getSigners();

    for (const account of accounts) {
        console.log(account.address);
    }
});

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

const config: HardhatUserConfig = {
    networks: {
        hardhat: {
        allowUnlimitedContractSize: false,
        },
        mainnet: {
            url: `https://mainnet.infura.io/v3/${process.env.INFURA_API_KEY}`,
        },
        ropsten: {
            url: `https://ropsten.infura.io/v3/${process.env.INFURA_API_KEY}`,
        },
        rinkeby: {
            url: `https://rinkeby.infura.io/v3/${process.env.INFURA_API_KEY}`,
            accounts: [`${process.env.RINKEBY_PRIVATE_KEY}`, ],
        },
        goerli: {
            url: `https://goerli.infura.io/v3/${process.env.INFURA_API_KEY}`,
        },
        kovan: {
            url: `https://kovan.infura.io/v3/${process.env.INFURA_API_KEY}`,
        },
    },
    etherscan: {
        // Your API key for Etherscan
        // Obtain one at https://etherscan.io/
        apiKey: process.env.ETHERSCAN_API_KEY,
    },
    solidity: {
        compilers: [DEFAULT_COMPILER_SETTINGS],
    },
    contractSizer: {
        alphaSort: false,
        disambiguatePaths: true,
        runOnCompile: false,
    },
}

export default config;
