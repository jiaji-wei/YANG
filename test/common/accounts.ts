import { MockProvider } from 'ethereum-waffle';
import { Wallet } from 'ethers';


const WALLET_USER_INDEXES = {
    CHI_DEPLOYER: 5,
    ALL_GOV: 6,
    YANG_DEPLOYER: 8,
    OTHER_TRADER0: 9,
    OTHER_TRADER1: 10,
}

export class AccountsFixture {
    wallets: Array<Wallet>;
    provider: MockProvider;

    constructor(wallets: Array<Wallet>, provider: MockProvider) {
        this.wallets = wallets;
        this.provider = provider;
    }

    yangDeployer() {
        return this._getAccount(WALLET_USER_INDEXES.YANG_DEPLOYER);
    }

    allGov() {
        return this._getAccount(WALLET_USER_INDEXES.ALL_GOV);
    }

    chiDeployer() {
        return this._getAccount(WALLET_USER_INDEXES.CHI_DEPLOYER)
    }

    otherTrader0() {
        return this._getAccount(WALLET_USER_INDEXES.OTHER_TRADER0)
    }

    otherTrader1() {
        return this._getAccount(WALLET_USER_INDEXES.OTHER_TRADER1)
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
