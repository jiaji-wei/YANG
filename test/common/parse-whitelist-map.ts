import { BigNumber, utils } from 'ethers';
import WhiteListTree from './whitelist-tree';

const { isAddress, getAddress } = utils;


interface MerkleDistributorInfo {
    merkleRoot: string;
    whitelist: {
        [account: string]: {
            proof: string[]
        }
    }
}

type InputFormat = string[];


export default function parseWhiteListMap(inputs: InputFormat): MerkleDistributorInfo {
    const accounts = inputs.map((account) => {
        if (!isAddress(account)) {
            throw new Error(`Found invalid address: ${account}`);
        }
        return getAddress(account);
    });
    const tree = new WhiteListTree(accounts);
    const whitelist = accounts.reduce<
        {[account: string]: { proof: string[] }}
        >((memo, address) => {
            memo[address] = {
                proof: tree.getHexProof(address)
            };
            return memo;
        }, {});
    return {
        merkleRoot: tree.getHexRoot(),
        whitelist: whitelist
    };
}
