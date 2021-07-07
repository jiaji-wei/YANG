import { ethers } from 'hardhat';


async function main() {
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangNFT = await YangNFTFactory.deploy();
    await YangNFT.deployed();

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0x5fB7Fd5AB0aD08fd5D7c341Cd7e877434b72ae51
    console.log(YangNFT.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

