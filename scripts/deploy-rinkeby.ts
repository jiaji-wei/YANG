import { ethers } from 'hardhat';


async function main() {
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangNFT = await YangNFTFactory.deploy();
    await YangNFT.deployed();

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0xBfb7003F5c8375C7B64519CE4fb5a9BaE8023853
    console.log(YangNFT.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

