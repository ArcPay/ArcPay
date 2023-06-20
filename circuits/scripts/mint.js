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

const sk1 = '0xb4b0bf302506d14eba9970593921a0bd219a10ebf66a0367851a278f9a8c3d08';
const pk1 = '0x8ca4cc18dc867aE7D87473f8460120168a895E7A';
const pk1Uint = 802933809494131860455082925493303288586736066170n;

const sk2 = '0xb81676dc516f1e4dcec657669e30d31e4454e67aa98574eca670b4509878290c';
const pk2 = '0x2C66bB06B88Bf3aB61aF23E70B0c8bE27b1e5930';
const pk2Uint = 253486562210967126009990789802080859110172940592n;

const stateTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });
const mintTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });

// allow a few deposits
const leaf1 = vmtree.poseidon([pk1Uint, 0, 10]);
const leaf2 = vmtree.poseidon([pk2Uint, 11, 15]);

mintTree.update(0, leaf1);
mintTree.update(1, leaf2);

const {pathIndices: pi1, pathElements: pe1} = mintTree.path(0);
expect(verifyMerkleProof({
    leaf: leaf1,
    root: mintTree.root,
    pathElements: pe1,
    pathIndices: pi1
})).to.be.true;

console.log(stateTree.root);
stateTree.update(0, 0);
console.log(stateTree.root);
const { pathIndices: si1, pathElements: se1 } = stateTree.path(0);

const input1 = vmtree.utils.stringifyBigInts({
    step_in: [mintTree.root, stateTree.root],
    sender: 0,
    recipient: pk1Uint,
    leaf_coins: [0, 10],
    mintPathElements: pe1,
    mintPathIndices: pi1,
    pathElements: se1,
    pathIndices: si1
});

console.log('input1', JSON.stringify(input1));

// prepare trees for next mint
mintTree.update(0,0);
stateTree.update(0, leaf1);
stateTree.update(1, 0);
const { pathIndices: si2, pathElements: se2 } = stateTree.path(1);

const { pathIndices: pi2, pathElements: pe2 } = mintTree.path(1);
expect(verifyMerkleProof({
    leaf: leaf2,
    root: mintTree.root,
    pathElements: pe2,
    pathIndices: pi2
})).to.be.true;

const input2 = vmtree.utils.stringifyBigInts({
    step_in: [mintTree.root, stateTree.root],
    sender: 0,
    recipient: pk2Uint,
    leaf_coins: [11, 15],
    mintPathElements: pe2,
    mintPathIndices: pi2,
    pathElements: se2,
    pathIndices: si2
});

console.log('input2', JSON.stringify(input2));

let novaJson = {};

for (var k in input1) {
    novaJson[k] = [input1[k], input2[k]];
}
novaJson.step_in = input1.step_in;
console.log('novaJson', JSON.stringify(novaJson));
