import MerkleTree from './merkle-tree';
import { utils } from 'ethers';
import { toBuffer } from 'ethereumjs-util';


export default class WhiteListTree {
    private readonly tree: MerkleTree;
    constructor(whitelist: string[]) {
        this.tree = new MerkleTree(
            whitelist.map((account) => {
                return WhiteListTree.toNode(account);
            })
        );
    }

    public static toNode(account: string): Buffer {
        return Buffer.from(
            utils.solidityKeccak256(['address'], [account]).substr(2),
            'hex'
        );
    }

    public static verifyProof(
        account: string,
        proof: string[],
        root: string
    ): boolean {
        let node = WhiteListTree.toNode(account);
        let proofBuf = proof.map((el) => toBuffer(el));
        let rootBuf = toBuffer(root);

        for (let item of proofBuf) {
            node = MerkleTree.combineAndHash(node, item);
        }
        return node.equals(rootBuf);
    }

    public getHexRoot(): string {
        return this.tree.getHexRoot();
    }

    public getHexProof(account: string): string[] {
        return this.tree.getHexProof(WhiteListTree.toNode(account));
    }
}
