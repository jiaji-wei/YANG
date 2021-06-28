import { ethers } from 'hardhat';

const Governance = '0x5a0350846f321524d0fBe0C6A94027E89bE23bE5';


async function main() {
    const YangViewFactory = await ethers.getContractFactory('YangView');
    const YangNFTFactory = await ethers.getContractFactory('YangNFTVault');
    const YangView = await YangViewFactory.deploy();
    await YangView.deployed();
    const YangNFT = await YangNFTFactory.deploy(Governance);
    await YangNFT.deployed();

    console.log('YANGView:')
    console.log(YangView.address) // 0x261F76d553139EA652C78211bdc68a3dF2c64B41
    console.log(YangView.deployTransaction.hash);

    console.log('YANGNFTVault')
    console.log(YangNFT.address) // 0xbB7F54758979166A34C40788Ed45796b0569aFD9
    console.log(YangNFT.deployTransaction.hash);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });

