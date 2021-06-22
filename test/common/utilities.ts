import bn from 'bignumber.js';
import { BigNumberish, BigNumber, utils, Wallet } from 'ethers'
import { isArray, isString } from 'lodash';
import { TestERC20 } from '../../typechain';

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

export const getMinTick = (tickSpacing: number): number => Math.ceil(-887272 / tickSpacing) * tickSpacing
export const getMaxTick = (tickSpacing: number): number => Math.floor(887272 / tickSpacing) * tickSpacing

export function convertTo18Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}

export function getPositionKey(address: string, lowerTick: number, upperTick: number): string {
  return utils.keccak256(utils.solidityPack(['address', 'int24', 'int24'], [address, lowerTick, upperTick]))
}

export const arrayWrap = (x: any) => {
    if (!isArray(x)) {
        return [x];
    } else {
        return x;
    }
}

// returns the sqrt price as a 64x96
export function encodePriceSqrt(reserve1: BigNumberish, reserve0: BigNumberish): BigNumber {
  return BigNumber.from(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString()
  )
}

export class ERC20Helper {
    ensureBalanceAndApprovals = async (
        account: Wallet,
        tokens: TestERC20 | Array<TestERC20>,
        balance: BigNumber,
        spender?: string
    ) => {
        for (let token of arrayWrap(tokens)) {
            await this.ensureBalance(account, token, balance);
            if (spender) {
                await this.ensureApproval(account, token, balance, spender);
            }
        }
    }

    ensureBalance = async (
        account: Wallet,
        token: TestERC20,
        balance: BigNumber
    ) => {
        const currentBalance = await token.balanceOf(account.address);
        if (currentBalance.lt(balance)) {
            await token.transfer(account.address, balance.sub(currentBalance));
        }
        return await token.balanceOf(account.address);
    }

    ensureApproval = async (
        account: Wallet,
        token: TestERC20,
        balance: BigNumber,
        spender: string
    ) => {
        const currentAllowance = await token.allowance(account.address, spender);
        if (currentAllowance.lt(balance)) {
            await token.connect(account).approve(spender, balance);
        }
    }
}
