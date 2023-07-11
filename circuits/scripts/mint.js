// const chalk = require('chalk');
import { expect }  from 'chai';
import { default as vmtree } from 'vmtree-sdk';

import { MerkleTree as FixedMerkleTree } from "fixed-merkle-tree";

class MerkleTree extends FixedMerkleTree {
    constructor({ hasher, levels = 20, leaves = [], zero = 0 }) {
        super(levels, leaves, {
            hashFunction: (left, right) => hasher([left, right]),
            zeroElement: zero,
        });
    };
};

function verifyMerkleProof({pathElements, pathIndices, leaf, root}) {
    pathElements.forEach((element, i) => {
        leaf = !pathIndices[i] ?
            vmtree.poseidon([leaf, element]) : vmtree.poseidon([element, leaf]);
    });
    return leaf == root;
}

const stateTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });
const mintTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });

// recipient secret keys = ['0xb4b0bf302506d14eba9970593921a0bd219a10ebf66a0367851a278f9a8c3d08', '0xb81676dc516f1e4dcec657669e30d31e4454e67aa98574eca670b4509878290c']
const data = [{recipient: 802933809494131860455082925493303288586736066170n, leaf_coins:[0, 10]}, {recipient: 253486562210967126009990789802080859110172940592n, leaf_coins: [11, 15]}]
const leaves = data.map((v) => vmtree.poseidon([v.recipient, v.leaf_coins[0], v.leaf_coins[1]]))

// fill up mint tree
leaves.forEach((leaf, i) => {
    mintTree.update(i, leaf)
})

// update state tree while emptying mint tree and generating circuit inputs
let inputs = data.map((datum, i) => {
    stateTree.update(i, 0); // initialises the leaf

    const {pathIndices: pi, pathElements: pe} = mintTree.path(i);
    expect(verifyMerkleProof({
        leaf: leaves[i],
        root: mintTree.root,
        pathElements: pe,
        pathIndices: pi
    })).to.be.true;
    
    const { pathIndices: si, pathElements: se } = stateTree.path(i);
    const input = vmtree.utils.stringifyBigInts({
        step_in: [mintTree.root, stateTree.root],
        sender: 0,
        recipient: datum.recipient,
        leaf_coins: datum.leaf_coins,
        mintPathElements: pe,
        mintPathIndices: pi,
        pathElements: se,
        pathIndices: si
    });
    
    // prepare trees for next mint
    mintTree.update(i,0);
    stateTree.update(i, leaves[i]);
    return input;
})

let novaJson = {
    step_in: inputs[0].step_in,
    private_inputs: inputs
};

console.log(JSON.stringify(novaJson, (_, v) => typeof v === "number" ? v.toString(): v, 4));
