import { ethers } from 'hardhat';


async function main() {
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangNFT = await YangNFTFactory.deploy();
    await YangNFT.deployed();

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0xb07F3328b4746969113CF5369e138eD6d42Aa47e
    console.log(YangNFT.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

