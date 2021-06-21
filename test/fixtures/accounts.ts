import { MockProvider } from 'ethereum-waffle';
import { Wallet } from 'ethers';


const WALLET_USER_INDEXES = {
    WETH_OWNER: 0,
    TOKENS_OWNER: 1,
    UNISWAP_ROOT: 2,
    CHI_DEPLOYER: 3,
    YANG_DEPLOYER: 4,
    LP_USER_0: 5,
    LP_USER_1: 6,
    LP_USER_2: 7,
    TRADER_USER_0: 8,
    TRADER_USER_1: 9,
    TRADER_USER_2: 10,
}

export class AccountsFixture {
    wallets: Array<Wallet>;
    provider: MockProvider;

    constructor(wallets, provider) {
        this.wallets = wallets;
        this.provider = provider;
    }

    wethOwner() {
        return this._getAccount(WALLET_USER_INDEXES.WETH_OWNER);
    }

    tokensOwner() {
        return this._getAccount(WALLET_USER_INDEXES.TOKENS_OWNER);
    }

    uniswapRootUser() {
        return this._getAccount(WALLET_USER_INDEXES.UNISWAP_ROOT);
    }

    lpUser0() {
        return this._getAccount(WALLET_USER_INDEXES.LP_USER_0);
    }

    lpUser1() {
        return this._getAccount(WALLET_USER_INDEXES.LP_USER_1);
    }

    lpUser2() {
        return this._getAccount(WALLET_USER_INDEXES.LP_USER_2);
    }

    lpUsers() {
        return [this.lpUser0(), this.lpUser1(), this.lpUser2()];
    }

    traderUser0() {
        return this._getAccount(WALLET_USER_INDEXES.TRADER_USER_0);
    }

    traderUser1() {
        return this._getAccount(WALLET_USER_INDEXES.TRADER_USER_1);
    }

    traderUser2() {
        return this._getAccount(WALLET_USER_INDEXES.TRADER_USER_2);
    }

    yangDeployer() {
        return this._getAccount(WALLET_USER_INDEXES.YANG_DEPLOYER);
    }

    chiDeployer() {
        return this._getAccount(WALLET_USER_INDEXES.CHI_DEPLOYER)
    }

    private _getAccount(idx: number): Wallet {
        if (idx < 0 || idx === undefined || idx === null) {
            throw new Error(`Invalid index: ${idx}`);
        }
        const account = this.wallets[idx];
        if (!account) {
            throw new Error(`Account ID ${idx} could not be loaded`);
        }
        return account;
    }
}
