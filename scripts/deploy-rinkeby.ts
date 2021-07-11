import { ethers } from 'hardhat';


async function main() {
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangNFT = await YangNFTFactory.deploy();
    await YangNFT.deployed();

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0x361582386541F9Bc612DB75b4270A1712e389F0e
    console.log(YangNFT.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

