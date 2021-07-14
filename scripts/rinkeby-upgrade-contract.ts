const { ethers, upgrades } = require('hardhat');

async function main() {
    const yangV2Factory = await ethers.getContractFactory('YangNFTVault');
    const yangV2Contract = await upgrades.upgradeProxy('0x68a0f259bd2c8faf7d515b5d03eba5c018cbc116',
                                                       yangV2Factory);
    console.log('Upgrade YangNFTVault') // 0x68a0f259bd2c8faf7d515b5d03eba5c018cbc116
    console.log(yangV2Contract.address)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
