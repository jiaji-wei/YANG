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
    YangView,
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


describe('CHIManager', () => {
  const wallets = provider.getWallets()
  const accounts = new AccountsFixture(wallets, provider);
  const gov = accounts.allGov();
  const other = accounts.otherTrader0();
  const trader = accounts.otherTrader1();
  const erc20_helper = new ERC20Helper();

  let context: ShareFixtureType;
  let yangNFT: YangNFTVault
  let yangView: YangView;
  let token0: TestERC20, token1: TestERC20, token2: TestERC20;
  let chiVaultDeployer: TestCHIVaultDeployer
  let chiManager: TestCHIManager
  let factory: IUniswapV3Factory
  let router: TestRouter
  let nft: INonfungiblePositionManager

  let pool0: string
  let pool1: string

  const vaultFee = 1e4

  before('create fixture loader', async () => {
      loadFixture = createFixtureLoader(wallets, provider)
  })
  beforeEach('load fixture', async () => {
      context = await loadFixture(shareFixture);

      pool0 = context.pool0;
      pool1 = context.pool1;
      nft = context.nft;
      yangNFT = context.yangNFT;
      yangView = context.yangView;
      chiVaultDeployer = context.chiVaultDeployer;
      chiManager = context.chiManager;
      token0 = context.token0;
      token1 = context.token1;
      token2 = context.token2;
      factory = context.factory;
      router = context.router;
  })

  async function mint(
    recipient: string,
    token0: string,
    token1: string,
    fee: number,
    vaultFee: number,
    caller: Wallet = gov
  ): Promise<{
    tokenId: number
    vault: string
  }> {
    const mintParams = {
      recipient,
      token0,
      token1,
      fee,
      vaultFee,
    }

    const { tokenId, vault } = await chiManager.connect(caller).callStatic.mint(mintParams)
    await chiManager.connect(caller).mint(mintParams)
    return {
      tokenId: tokenId.toNumber(),
      vault,
    }
  }

  describe('Mint CHI NFT', async () => {
    describe('success cases', () => {
      it('succeeds for mint', async () => {
         //non-existent v3 pool
        await expect(mint(gov.address, USDCAddress, USDTAddress, FeeAmount.MEDIUM, vaultFee)).to.be.revertedWith(
          'Non-existent pool'
        )
        // more than FEE_BASE
        await expect(mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, 1e6)).to.be.revertedWith('f')

        const { tokenId: tokenId1 } = await mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, vaultFee)
        expect(gov.address).to.eq(await chiManager.ownerOf(tokenId1))

        expect(await chiManager.balanceOf(gov.address)).to.eq(1)

        const { tokenId: tokenId2, vault: vaultAddress } = await mint(
            gov.address,
            token0.address,
            token1.address,
            FeeAmount.MEDIUM,
            vaultFee
        )
        expect(tokenId2).to.eq(tokenId1 + 1)
        expect(gov.address).to.eq(await chiManager.ownerOf(tokenId2))

        expect(await chiManager.balanceOf(gov.address)).to.eq(2)

        const chiInfo = await chiManager.chi(tokenId2)
        expect(chiInfo.owner).to.eq(gov.address)
        expect(chiInfo.operator).to.eq(gov.address)
        expect(chiInfo.pool).to.eq(await factory.getPool(token0.address, token1.address, FeeAmount.MEDIUM))
        expect(chiInfo.vault).to.eq(vaultAddress)
        expect(chiInfo.accruedProtocolFees0).to.eq(0)
        expect(chiInfo.accruedProtocolFees1).to.eq(0)
        expect(chiInfo.fee).to.eq(vaultFee)
        expect(chiInfo.totalShares).to.eq(0)
      })

      it('succeeds for approve a operator', async () => {
        const { tokenId: tokenId1 } = await mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, vaultFee)
        expect(gov.address).to.eq(await chiManager.ownerOf(tokenId1))

        let chi1 = await chiManager.chi(tokenId1)

        expect(chi1.owner).to.eq(gov.address)
        expect(chi1.operator).to.eq(gov.address)

        await chiManager.connect(gov).approve(other.address, tokenId1)

        chi1 = await chiManager.chi(tokenId1)
        expect(chi1.owner).to.eq(gov.address)
        expect(chi1.operator).to.eq(other.address)

        const operator = await chiManager.getApproved(tokenId1)
        expect(operator).to.eq(ZeroAddress)
        // not override getApproved, but override _approve, so operator is zero address
        //expect(operator).to.eq(other.address)
      })
    })
    describe('fails cases', () => {
      it('fails if minter is not a gov', async () => {
        await expect(
          mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, vaultFee, wallets[1])
        ).to.be.revertedWith('gov')
      })
    })
  })

  describe('Manage CHI', async () => {
    const tokenAmount0 = convertTo18Decimals(10000)
    const tokenAmount1 = convertTo18Decimals(10000)
    const startingTick = 0
    const feeAmount = FeeAmount.MEDIUM
    const tickSpacing = TICK_SPACINGS[feeAmount]
    const minTick = getMinTick(tickSpacing)
    const maxTick = getMaxTick(tickSpacing)
    let pool: IUniswapV3Pool
    let chivault: TestCHIVault
    let tokenId1: number
    // set inital price
    // set 1:1
    const initPrice = encodePriceSqrt(1, 1)
    beforeEach('Mint CHI', async () => {
      // add liquidity
      pool = (await ethers.getContractAt('IUniswapV3Pool', pool0)) as IUniswapV3Pool;

      await token0.approve(router.address, constants.MaxUint256)
      await token1.approve(router.address, constants.MaxUint256)

      expect((await pool.slot0()).tick).to.eq(startingTick)
      expect((await pool.slot0()).sqrtPriceX96).to.eq(initPrice)
      // wait for manager test
      await router.mint(pool0, minTick, maxTick, convertTo18Decimals(1))

      const { tokenId, vault } = await mint(gov.address, token0.address, token1.address, FeeAmount.MEDIUM, vaultFee)
      tokenId1 = tokenId
      chivault = (await ethers.getContractAt('TestCHIVault', vault)) as TestCHIVault;

      // deposit to YANG
      await erc20_helper.ensureBalanceAndApprovals(trader, [token0, token1, token2], MaxUint128, yangNFT.address)
      let _yangId = await yangNFT.connect(gov).callStatic.mint(trader.address);
      await yangNFT.connect(gov).mint(trader.address);
      let yangId = _yangId.toNumber();
      await yangNFT.connect(trader).deposit(yangId, token0.address, tokenAmount0, token1.address, tokenAmount1)
    })
    describe('success cases', () => {
      it('set gov', async () => {
        await chiManager.connect(gov).setGovernance(other.address);
        expect(await chiManager.chigov()).to.eq(gov.address)
        expect(await chiManager.nextgov()).to.eq(other.address)
        await chiManager.connect(other).acceptGovernance()
        expect(await chiManager.chigov()).to.eq(other.address)
        expect(await chiManager.nextgov()).to.eq(ZeroAddress)
      })
      it('add and remove range', async () => {
        await chiManager.connect(gov).addRange(tokenId1, minTick, maxTick)
        expect(await chivault.getRangeCount()).to.eq(1)
        const ticks01 = await chivault.getRange(0)
        expect(ticks01.tickLower).to.eq(minTick)
        expect(ticks01.tickUpper).to.eq(maxTick)

        // add the same tick
        await chiManager.connect(gov).addRange(tokenId1, minTick, maxTick)
        expect(await chivault.getRangeCount()).to.eq(1)
        const ticks02 = await chivault.getRange(0)
        expect(ticks02.tickLower).to.eq(minTick)
        expect(ticks02.tickUpper).to.eq(maxTick)

        await chiManager.connect(gov).removeRange(tokenId1, minTick, maxTick)
        expect(await chivault.getRangeCount()).to.eq(0)
      })

      it('subscribe and unsubscribe', async () => {
        expect(await token0.balanceOf(yangNFT.address)).to.eq(tokenAmount0)
        expect(await token1.balanceOf(yangNFT.address)).to.eq(tokenAmount1)
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        const _share = await yangNFT.connect(trader).callStatic.subscribe(subscribeParam)
        await yangNFT.connect(trader).subscribe(subscribeParam);
        expect(await token0.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(9000))
        expect(await token1.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(9000))

        const unsubscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          shares: _share,
          amount0Min: convertTo18Decimals(1000),
          amount1Min: convertTo18Decimals(1000),
        }
        await yangNFT.connect(trader).unsubscribe(unsubscribeParam)
        expect(await token0.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(10000))
        expect(await token1.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(10000))
      })

      it('add liquidity and remove liquidity', async () => {
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yangNFT.connect(trader).subscribe(subscribeParam)
        expect(await token0.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(9000))
        expect(await token1.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(9000))
        // let token0 and token1 in all tick
        // means it should be 1:1
        await chiManager.connect(gov).addRange(tokenId1, minTick, maxTick)
        await chiManager.connect(gov).addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))

        await yangNFT.connect(trader).subscribe(subscribeParam)
        expect(await token0.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(8000))
        expect(await token1.balanceOf(yangNFT.address)).to.eq(convertTo18Decimals(8000))
        await chiManager.connect(gov).addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))

        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(2001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(2001))

        await chiManager.connect(gov).removeAllLiquidityFromPosition(tokenId1, 0)
        // hmm.. some leave in pool
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1).add(1))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1).add(1))
      })

      it('swap and calculate fee', async () => {
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        await yangNFT.connect(trader).subscribe(subscribeParam)
        await chiManager.connect(gov).addRange(tokenId1, minTick, maxTick)
        await chiManager.connect(gov).addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001))
        const { amount0Delta, amount1Delta, nextSqrtRatio } = await router.callStatic.getSwapResult(
          await chivault.pool(),
          true,
          convertTo18Decimals(1),
          MIN_SQRT_RATIO.add(1)
        )
        await router.getSwapResult(await chivault.pool(), true, convertTo18Decimals(1), MIN_SQRT_RATIO.add(1))
        expect(await token0.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001).add(amount0Delta))
        expect(await token1.balanceOf(await chivault.pool())).to.eq(convertTo18Decimals(1001).add(amount1Delta))

        await chivault.harvestFee()
        // v3 fee 0.3% and protocol fee 1%
        expect(await chivault.accruedProtocolFees0()).be.eq(
          convertTo18Decimals(1)
            .mul(3)
            .div(1000)
            .mul(vaultFee)
            .div(1e6)
            .mul(convertTo18Decimals(1000))
            .div(convertTo18Decimals(1001))
        )
        expect(await chivault.accruedProtocolFees1()).be.eq(0)
      })
      it('swap and remove liquidity', async () => {
        const subscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          amount0Desired: convertTo18Decimals(1000),
          amount1Desired: convertTo18Decimals(1000),
          amount0Min: 0,
          amount1Min: 0,
        }
        const _share = await yangNFT.connect(trader).callStatic.subscribe(subscribeParam)
        await yangNFT.connect(trader).subscribe(subscribeParam)
        await chiManager.connect(gov).addRange(tokenId1, minTick, maxTick)
        await chiManager.connect(gov).addLiquidityToPosition(tokenId1, 0, convertTo18Decimals(1000), convertTo18Decimals(1000))
        const { amount0Delta, amount1Delta, nextSqrtRatio } = await router.callStatic.getSwapResult(
          await chivault.pool(),
          true,
          convertTo18Decimals(1),
          MIN_SQRT_RATIO.add(1)
        )
        await router.getSwapResult(await chivault.pool(), true, convertTo18Decimals(1), MIN_SQRT_RATIO.add(1))
        await chivault.harvestFee()
        const unsubscribeParam = {
          yangId: 1,
          chiId: tokenId1,
          shares: _share,
          amount0Min: 0,
          amount1Min: 0,
        }
        await yangNFT.connect(trader).unsubscribe(unsubscribeParam)
        // 29970029970029 is protocol fee
        expect(await token0.balanceOf(yangNFT.address)).to.eq(
          tokenAmount0
            .add(amount0Delta.mul(convertTo18Decimals(1000)).div(convertTo18Decimals(1001)))
            .sub(29970029970029)
        )
        expect(await token1.balanceOf(yangNFT.address)).to.eq(
          tokenAmount1.add(amount1Delta.mul(convertTo18Decimals(1000)).div(convertTo18Decimals(1001))).sub(3)
        )
      })
    })
  })
})

