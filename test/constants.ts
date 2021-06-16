import { BigNumberish, BigNumber, Wallet } from 'ethers';
import { ethers, waffle } from 'hardhat';
import bn from 'bignumber.js';
import { isArray, isString } from 'lodash';
import {
    TestERC20
} from '../../typechain';


bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 });

export const MAX_GAS_LIMIT = 12_450_000;
export const BN = BigNumber.from;
export const BNe = (n: BigNumberish, exponent: BigNumberish) => BN(n).mul(BN(10).pow(exponent));
export const BNe18 = (n: BigNumberish) => BNe(n, 18);
export const provider = waffle.provider;
export const createFixtureLoader = waffle.createFixtureLoader

export const arrayWrap = (x: any) => {
    if (!isArray(x)) {
        return [x];
    } else {
        return x;
    }
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
