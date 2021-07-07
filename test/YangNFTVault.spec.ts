import { BigNumber, constants, Wallet } from 'ethers';
import { expect } from 'chai';
import { ethers, waffle } from 'hardhat';

import { shareFixture, ShareFixtureType } from './common/fixtures';
import {
    FeeAmount,
    TICK_SPACINGS,
    ZeroAddress,
    MaxUint128,
    MIN_SQRT_RATIO,
    MAX_SQRT_RATIO,
    USDCAddress,
    USDTAddress,
} from './common/constants';
import {
    convertTo18Decimals,
    getMinTick,
    getMaxTick,
    getPositionKey,
    encodePriceSqrt,
    ERC20Helper,
} from './common/utilities';
import { AccountsFixture } from './common/accounts';

import {
    IUniswapV3Factory,
    IUniswapV3Pool,
    TestERC20,
    YangNFTVault,
    TestCHIVaultDeployer,
    TestCHIVault,
    TestCHIManager,
    TestRouter,
} from '../typechain';
import { INonfungiblePositionManager } from '../types/INonfungiblePositionManager';

const provider = waffle.provider;
const createFixtureLoader = waffle.createFixtureLoader;
type LoadFixtureFunction = ReturnType<typeof createFixtureLoader>;
let loadFixture: LoadFixtureFunction;


describe('YangNFTVault', () => {
    const wallets = provider.getWallets();
    const accounts = new AccountsFixture(wallets, provider);
    const gov = accounts.allGov();
    const other = accounts.otherTrader0();
    const trader = accounts.otherTrader1();
    const erc20_helper = new ERC20Helper();

    let context: ShareFixtureType;
    let yangNFT: YangNFTVault;
    let token0: TestERC20, token1: TestERC20, token2: TestERC20;
    let chiVaultDeployer: TestCHIVaultDeployer;
    let chiManager: TestCHIManager;
    let factory: IUniswapV3Factory;
    let router: TestRouter;
    let nft: INonfungiblePositionManager;

    let pool0: string;
    let pool1: string;

    const vaultFee = 1e4;

    before('create fixture loader', async () => {
        loadFixture = createFixtureLoader(wallets, provider);
    })
    beforeEach('load fixture', async () => {
        context = await loadFixture(shareFixture);
        pool0 = context.pool0;
        pool1 = context.pool1;
        nft = context.nft;
        yangNFT = context.yangNFT;
        chiVaultDeployer = context.chiVaultDeployer;
        chiManager = context.chiManager;
        token0 = context.token0;
        token1 = context.token1;
        token2 = context.token2;
        factory = context.factory;
        router = context.router;
    })

    async function mintCHI(
        recipient: string,
        token0: string,
        token1: string,
        fee: number,
        vaultFee: number,
        caller: Wallet = gov
    ): Promise<{tokenId: number, vault: string}>
    {
        const mintParams = {
            recipient,
            token0,
            token1,
            fee,
            vaultFee
        };
        const { tokenId, vault } = await chiManager.connect(caller).callStatic.mint(mintParams);
        await chiManager.connect(caller).mint(mintParams);
        return {
            tokenId: tokenId.toNumber(),
            vault
        };
    }
    describe('Mint YANG NFT', async () => {
        describe('success cases', () => {
            it('mint success', async () => {
                const yangId = await yangNFT.connect(gov).callStatic.mint(trader.address);
                await yangNFT.connect(gov).mint(trader.address);
                expect(trader.address).to.eq(await yangNFT.ownerOf(yangId));
                expect(await yangNFT.balanceOf(trader.address)).to.eq(1);
            })

            it('success approve and transfer', async () => {
                const yangId = await yangNFT.connect(gov).callStatic.mint(trader.address);
                await yangNFT.connect(gov).mint(trader.address);

                await expect(yangNFT.transferFrom(trader.address, other.address, yangId))
                    .to.be.revertedWith('ERC721: transfer caller is not owner nor approved');
                await yangNFT.connect(trader).approve(other.address, yangId);
                await yangNFT.connect(other).transferFrom(trader.address, other.address, yangId);
                expect(other.address).to.eq(await yangNFT.ownerOf(yangId));
            })
            it('every one can mint NFT', async () => {
                const yangId = await yangNFT.connect(trader).callStatic.mint(trader.address);
                await yangNFT.connect(trader).mint(trader.address);
                expect(trader.address).to.eq(await yangNFT.ownerOf(yangId));
                expect(await yangNFT.balanceOf(trader.address)).to.eq(1);
            })
        })
        describe('fail cases', () => {
            it('each user can only mint one NFT', async () => {
                const yangId = await yangNFT.connect(gov).callStatic.mint(trader.address);
                await yangNFT.connect(gov).mint(trader.address);
                expect(trader.address).to.eq(await yangNFT.ownerOf(yangId));
                expect(await yangNFT.balanceOf(trader.address)).to.eq(1);
                await expect(yangNFT.connect(gov).mint(trader.address)).to.be.revertedWith('OO');
            })
        })
    })
    describe('YangNFT and CHIManager', async () => {
        const tokenAmount0 = convertTo18Decimals(10000);
        const tokenAmount1 = convertTo18Decimals(10000);
        const startingTick = 0;
        const feeAmount = FeeAmount.MEDIUM;
        const tickSpacing = TICK_SPACINGS[feeAmount];
        const minTick = getMinTick(tickSpacing);
        const maxTick = getMaxTick(tickSpacing);
        const initPrice = encodePriceSqrt(1, 1)
        let pool: IUniswapV3Pool;
        let chivault: TestCHIVault;
        let chiId: number;
        let yangId: number;

        beforeEach('Mint CHI', async () => {
            // add liquidity
            pool = (await ethers.getContractAt('IUniswapV3Pool', pool0)) as IUniswapV3Pool;

            await token0.approve(router.address, constants.MaxUint256)
            await token1.approve(router.address, constants.MaxUint256)

            expect((await pool.slot0()).tick).to.eq(startingTick)
            expect((await pool.slot0()).sqrtPriceX96).to.eq(initPrice)
            // wait for manager test
            await router.mint(pool0, minTick, maxTick, convertTo18Decimals(1))

            const { tokenId, vault } = await mintCHI(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, vaultFee)
            chiId = tokenId
            chivault = (await ethers.getContractAt('TestCHIVault', vault)) as TestCHIVault;

            // deposit to YANG
            await erc20_helper.ensureBalanceAndApprovals(trader, [token0, token1, token2], convertTo18Decimals(10000), yangNFT.address)
            const _yangId = await yangNFT.connect(gov).callStatic.mint(trader.address);
            await yangNFT.connect(gov).mint(trader.address);
            yangId = _yangId.toNumber();
        });

        it('trader amount', async () => {
            expect(await token0.balanceOf(trader.address)).to.eq(tokenAmount0);
            expect(await token1.balanceOf(trader.address)).to.eq(tokenAmount1);
        })

        it('getShares', async() => {
            expect(await token0.balanceOf(yangNFT.address)).to.eq(0)
            expect(await token1.balanceOf(yangNFT.address)).to.eq(0)

            const amountDesired = convertTo18Decimals(1000);
            const calShare = await yangNFT.getShares(chiId, amountDesired, amountDesired);
            await expect(calShare).to.gt(0);
            const subscribeParam = {
                yangId: yangId,
                chiId: chiId,
                amount0Desired: convertTo18Decimals(1000),
                amount1Desired: convertTo18Decimals(1000),
                amount0Min: 0,
                amount1Min: 0,
            }
            const {amount0, amount1, shares} = await yangNFT.connect(trader).callStatic.subscribe(subscribeParam)
            await yangNFT.connect(trader).subscribe(subscribeParam);
            await expect(shares).to.eq(calShare);
        })

        it('getAmounts', async () => {
            expect(await token0.balanceOf(trader.address)).to.eq(tokenAmount0);
            expect(await token1.balanceOf(trader.address)).to.eq(tokenAmount1);

            const [amount0, amount1] = await yangNFT.getAmounts(yangId, chiId);
            await expect(amount0).to.eq(0);
            await expect(amount1).to.eq(0);

            const subscribeParam = {
                yangId: yangId,
                chiId: chiId,
                amount0Desired: convertTo18Decimals(1000),
                amount1Desired: convertTo18Decimals(1000),
                amount0Min: 0,
                amount1Min: 0,
            }
            const [_amount0, _amount1, _shares] = await yangNFT.connect(trader).callStatic.subscribe(subscribeParam)
            await yangNFT.connect(trader).subscribe(subscribeParam);

            const before1 = await yangNFT.yangPositions(yangId, chiId);
            const before2 = await yangNFT.yangPositions(yangId, chiId);
            const calshares = _shares.div(2);
            const unsubscribeParam = {
                yangId: yangId,
                chiId: chiId,
                shares: calshares,
                amount0Min: convertTo18Decimals(100),
                amount1Min: convertTo18Decimals(100),
            }
            await yangNFT.connect(trader).unsubscribe(unsubscribeParam);
            const after1 = await yangNFT.yangPositions(yangId, chiId);
            const after2 = await yangNFT.yangPositions(yangId, chiId);
            const [v1, v2] = await yangNFT.getAmounts(yangId, chiId);
            await expect(before1[2].sub(after1[2])).to.eq(v1);
            await expect(before2[2].sub(after2[2])).to.eq(v2);
        })
    })
})
