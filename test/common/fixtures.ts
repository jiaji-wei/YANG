import { Fixture } from 'ethereum-waffle';
import { constants, BigNumber } from 'ethers';
import { ethers, waffle, upgrades } from 'hardhat';

import UniswapV3Pool from '@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json';
import UniswapV3FactoryJson from '@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json';
import NFTDescriptorJson from '@uniswap/v3-periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json';
import NonfungiblePositionManagerJson from '@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json';
import NonfungibleTokenPositionDescriptor from '@uniswap/v3-periphery/artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json';

import {
    TestERC20,
    YangNFTVault,
    TestCHIVaultDeployer,
    TestCHIVault,
    TestCHIManager,
    IUniswapV3Factory,
    IUniswapV3Pool,
    TestRouter,
} from "../../typechain";
import { AccountsFixture } from './accounts';
import { encodePriceSqrt } from './utilities';
import { FeeAmount, MAX_GAS_LIMIT } from './constants'

import WETH9 from '../../types/WETH9.json';
import { IWETH9 } from '../../types/IWETH9';
import { INonfungiblePositionManager } from '../../types/INonfungiblePositionManager';
import { NFTDescriptor } from '../../types/NFTDescriptor'
import { linkLibraries } from '../../types/linkLibraries';


type UniswapV3FactoryFixtureType = {
    factory: IUniswapV3Factory
}

const v3CoreFactoryFixture: Fixture<IUniswapV3Factory> = async ([wallet]) => {
    return ((await waffle.deployContract(wallet, {
        bytecode: UniswapV3FactoryJson.bytecode,
        abi: UniswapV3FactoryJson.abi,
    })) as unknown) as IUniswapV3Factory
}

export const v3RouterFixture: Fixture<{
    weth9: IWETH9,
    factory: IUniswapV3Factory,
    router: TestRouter
}> = async ([wallet], provider) => {
    const weth9 = (await waffle.deployContract(wallet, {
                        bytecode: WETH9.bytecode,
                        abi: WETH9.abi
                    })) as IWETH9;
    const factory = await v3CoreFactoryFixture([wallet], provider);

    const routerFactory = await ethers.getContractFactory('TestRouter');
    const router = (await routerFactory.deploy()) as TestRouter;

    return { factory, weth9, router }
}

const tokenFixture: Fixture<{token0: TestERC20, token1: TestERC20, token2: TestERC20}> = async (wallets, provider) => {
    const tokenFactory = await ethers.getContractFactory('TestERC20');
    const tokens = (await Promise.all([
        tokenFactory.deploy(constants.MaxUint256.div(2)),
        tokenFactory.deploy(constants.MaxUint256.div(2)),
        tokenFactory.deploy(constants.MaxUint256.div(2)),
    ])) as [TestERC20, TestERC20, TestERC20];
    const [token0, token1, token2] = tokens.sort((a, b) => (a.address.toLowerCase() < b.address.toLowerCase() ? -1 : 1));
    return { token0, token1, token2 };
}

type UniswapV3FixtureType = {
    weth9: IWETH9,
    factory: IUniswapV3Factory,
    router: TestRouter,
    nft: INonfungiblePositionManager,
    token0: TestERC20,
    token1: TestERC20,
    token2: TestERC20
}

const uniswapV3Fixture: Fixture<UniswapV3FixtureType> = async (wallets, provider) => {
    const {weth9, factory, router} = await v3RouterFixture(wallets, provider);
    const {token0, token1, token2} = await tokenFixture(wallets, provider);
    const nftDescriptorLibrary = (await waffle.deployContract(wallets[0], {
                                    bytecode: NFTDescriptorJson.bytecode,
                                    abi: NFTDescriptorJson.abi,
                                })) as NFTDescriptor;
    const linkedBytecode = linkLibraries(
        {
        bytecode: NonfungibleTokenPositionDescriptor.bytecode,
        linkReferences: {
            'NFTDescriptor.sol': {
            NFTDescriptor: [
                {
                length: 20,
                start: 1261,
                },
            ],
            },
        },
        },
        {
        NFTDescriptor: nftDescriptorLibrary.address,
        }
    );
    const positionDescriptor = await waffle.deployContract(
        wallets[0],
        {
            bytecode: linkedBytecode,
            abi: NonfungibleTokenPositionDescriptor.abi,
        },
        [token0.address]
    );
    const nftFactory = new ethers.ContractFactory(
        NonfungiblePositionManagerJson.abi,
        NonfungiblePositionManagerJson.bytecode,
        wallets[0]
    );
    const nft = (await nftFactory.deploy(
        factory.address,
        weth9.address,
        positionDescriptor.address
    )) as INonfungiblePositionManager;
    return {
        weth9,
        factory,
        router,
        nft,
        token0,
        token1,
        token2,
    }
}

export type ShareFixtureType = {
    weth9: IWETH9,
    factory: IUniswapV3Factory,
    router: TestRouter,
    nft: INonfungiblePositionManager
    token0: TestERC20,
    token1: TestERC20,
    token2: TestERC20,
    pool0: string,
    pool1: string,
    yangNFT: YangNFTVault,
    chiVaultDeployer: TestCHIVaultDeployer,
    chiManager: TestCHIManager,
}


export const shareFixture: Fixture<ShareFixtureType> = async (wallets, provider) => {
    const {
        weth9,
        factory,
        router,
        nft,
        token0,
        token1,
        token2
    } = await uniswapV3Fixture(wallets, provider);

    const accounts = new AccountsFixture(wallets, provider);
    const yangDeployer = accounts.yangDeployer();
    const chiDeployer = accounts.chiDeployer();
    const allGov = accounts.allGov();

    const yangNFTFactory = await ethers.getContractFactory('YangNFTVault', yangDeployer);
    const yangNFT = (await upgrades.deployProxy(yangNFTFactory, [1])) as YangNFTVault
    //const yangNFT = (await yangNFTFactory.deploy()) as YangNFTVault;

    const chiVaultDeployerFactory = await ethers.getContractFactory('TestCHIVaultDeployer', chiDeployer);
    const chiManagerFactory = await ethers.getContractFactory('TestCHIManager', chiDeployer);
    const chiVaultDeployer = (await chiVaultDeployerFactory.deploy()) as TestCHIVaultDeployer;
    const chiManager = (await chiManagerFactory.deploy(
        factory.address,
        yangNFT.address,
        chiVaultDeployer.address,
        allGov.address
    )) as TestCHIManager;

    await chiVaultDeployer.setCHIManager(chiManager.address);
    await yangNFT.setCHIManager(chiManager.address);

    const fee = FeeAmount.MEDIUM;
    await nft.createAndInitializePoolIfNecessary(
        token0.address,
        token1.address,
        fee,
        encodePriceSqrt(1, 1)
    );
    await nft.createAndInitializePoolIfNecessary(
        token1.address,
        token2.address,
        fee,
        encodePriceSqrt(1, 1)
    );
    const pool0 = await factory.getPool(token0.address, token1.address, fee);
    const pool1 = await factory.getPool(token1.address, token2.address, fee);

    return {
        weth9,
        factory,
        router,
        nft,
        token0,
        token1,
        token2,
        pool0,
        pool1,
        yangNFT,
        chiVaultDeployer,
        chiManager,
    };
}
