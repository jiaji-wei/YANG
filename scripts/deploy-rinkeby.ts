import { ethers } from 'hardhat';


async function main() {
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangNFT = await YangNFTFactory.deploy();
    await YangNFT.deployed();

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0x0E1d4ac1F1858135b02F64CF6d47caEa5B218BAA
    console.log(YangNFT.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

