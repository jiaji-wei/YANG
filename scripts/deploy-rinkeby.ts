import { ethers } from 'hardhat';


async function main() {
    const YangViewFactory = await ethers.getContractFactory('YangView');
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangView = await YangViewFactory.deploy();
    await YangView.deployed();
    const YangNFT = await YangNFTFactory.deploy();
    await YangNFT.deployed();

    console.log('YANGView:')
    console.log(YangView.address) // 0x2Ba5310482a9Fbb242633d8a82027af41FB4B579
    console.log(YangView.deployTransaction.hash);

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0xd1309B94DAcA28bc402694a60Aee53089cfff5E5
    console.log(YangNFT.deployTransaction.hash);

    await YangNFT.setYangView(YangView.address);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

