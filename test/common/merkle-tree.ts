import { bufferToHex, keccak256 } from 'ethereumjs-util';


type OptionalBuffer = Buffer | undefined;


export default class MerkleTree {
    private readonly elements: Buffer[];
    private readonly bufferElementPositionIndex: { [hexElement: string]: number };
    private readonly layers: Buffer[][];

    constructor(elements: Buffer[]) {
        this.elements = [...elements];
        this.elements.sort(Buffer.compare);

        // remove duplicate elements
        this.elements = this.elements.filter((el, index, arr) => {
            return index == 0 || !arr[index - 1].equals(el);
        });
        this.bufferElementPositionIndex = this.elements.reduce<{ [hexElement: string]: number }>((memo, el, index) => {
            memo[bufferToHex(el)] = index;
            return memo;
        }, {});
        this.layers = this.getLayers(this.elements);
    }

    getLayers(elements: Buffer[]): Buffer[][] {
        if (elements.length == 0) {
            throw new Error('empty tree');
        }
        const layers = [];
        layers.push(elements);
        while(layers[layers.length - 1].length > 1) {
            layers.push(this.getNextLayer(layers[layers.length - 1]));
        }
        return layers;
    }

    getNextLayer(elements: Buffer[]): Buffer[] {
        return elements.reduce<Buffer[]>((layer, el, index, arr) => {
            if (index % 2 == 0) {
                layer.push(MerkleTree.combineAndHash(el, arr[index + 1]));
            }
            return layer;
        }, []);
    }

    static combineAndHash(first: Buffer, second: Buffer): Buffer {
        if (!first) {
            return second;
        } else if (!second) {
            return first;
        } else {
            return keccak256(Buffer.concat([first, second].sort(Buffer.compare)));
        }
    }

    getRoot(): Buffer {
        return this.layers[this.layers.length - 1][0];
    }

    getHexRoot(): string {
        return bufferToHex(this.getRoot());
    }

    getProof(el: Buffer): Buffer[] {
        let index = this.bufferElementPositionIndex[bufferToHex(el)];
        if (typeof index !== 'number') {
            throw new Error('element does not exist in merkle tree');
        }
        return this.layers.reduce<Buffer[]>((proof, layer) => {
            const pairIndex = index % 2 == 0 ? index + 1 : index - 1;
            const pairElement = layer[pairIndex];
            if (Buffer.isBuffer(pairElement)) {
                proof.push(pairElement);
            }
            index = Math.floor(index / 2);
            return proof;
        }, []);
    }

    getHexProof(el: Buffer): string[] {
        const proof = this.getProof(el);
        if (proof.some((el) => !Buffer.isBuffer(el))) {
            throw new Error('Proof is not an array of Buffer');
        } else {
            return proof.map((el) => '0x' + el.toString('hex'));
        }
    }
}
