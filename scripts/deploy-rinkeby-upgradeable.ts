const { ethers, upgrades } = require('hardhat');

async function main () {
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const instance = await upgrades.deployProxy(YangNFTFactory);
    await instance.deployed();

    console.log('YANGNFTVault')
    console.log(instance.address) // 0xb07F3328b4746969113CF5369e138eD6d42Aa47e
    console.log(instance.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
