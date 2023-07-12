import { ProjectivePoint, signAsync } from '@noble/secp256k1';
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

const stateTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });

function bigint_to_array(n/*: number*/, k/*: number*/, x/*: bigint*/) {
    let mod = 1n;
    for (var idx = 0; idx < n; idx++) {
        mod = mod * 2n;
    }

    let ret = [];
    var x_temp = x;
    for (var idx = 0; idx < k; idx++) {
        ret.push(x_temp % mod);
        x_temp = x_temp / mod;
    }
    return ret;
}

// bigendian
function bigint_to_Uint8Array(x) {
    var ret = new Uint8Array(32);
    for (var idx = 31; idx >= 0; idx--) {
        ret[idx] = Number(x % 256n);
        x = x / 256n;
    }
    return ret;
}

var privkeys = [88549154299169935420064281163296845505587953610183896504176354567359434168161n,
                               37706893564732085918706190942542566344879680306879183356840008504374628845468n,
                               90388020393783788847120091912026443124559466591761394939671630294477859800601n,
                               110977009687373213104962226057480551605828725303063265716157300460694423838923n];
var ethAddrsHex = ['0x4eaB0fA55a6c71c0c23BD0E67C06682b4Ce78A7f', '0xda1EA97d4c6D723125B26E4a1441C399d0EA0bE4', '0x05b9Df7825DE3c65A7D0386bD470F32a7008bC0c', '0xb032BA0CbF94CfE9A377aD4060624cA31CEEdE43'];
var ethAddrsBigInt = [449116070504281332671503011463517494968310008447n, 1245243775008760871701837986296674110984394771428n, 32690058639829526695160611728147099830035463180n, 1005913620148149221978770586875249574770925035075n];

stateTree.update(0, vmtree.poseidon([ethAddrsBigInt[0], 0n, 10n]));
stateTree.update(1, vmtree.poseidon([ethAddrsBigInt[1], 12n, 15n]));
stateTree.update(2, 0);
stateTree.update(3, 0);
stateTree.update(4, 0);

async function generateInput(privKey, sender, receiver, leafCoins, leafIndex) {
    let msghash_bigint = vmtree.poseidon([leafCoins[0], leafCoins[1], receiver]);

    // in compact format: r (big-endian), 32-bytes + s (big-endian), 32-bytes
    var sig/*: Uint8Array*/ = await signAsync(bigint_to_Uint8Array(msghash_bigint), bigint_to_Uint8Array(privKey));
    var pubKey = ProjectivePoint.fromPrivateKey(privKey);

    const {pathIndices, pathElements} = stateTree.path(leafIndex);
    const input = vmtree.utils.stringifyBigInts({
        step_in: [stateTree.root],
        sender: sender,
        recipient: 0n,
        leaf_coins: leafCoins,
        pathElements: pathElements,
        pathIndices: pathIndices,
        r: bigint_to_array(64, 4, sig.r),
        s: bigint_to_array(64, 4, sig.s),
        msghash: bigint_to_array(64, 4, msghash_bigint),
        pubkey: [bigint_to_array(64, 4, pubKey.x), bigint_to_array(64, 4, pubKey.y)]
    });
    return input;
}

// user0 withdraws the first leaf.
const input0 = await generateInput(privkeys[0], ethAddrsBigInt[0], 0n, [0n, 10n], 0);

stateTree.update(0, vmtree.poseidon([0, 0, 10]));

const input1 = await generateInput(privkeys[1], ethAddrsBigInt[1], 0n, [12n, 15n], 1);

let novaJson = {
    step_in: input1.step_in,
    private_inputs: [input0, input1]
};

console.log(JSON.stringify(novaJson, (_, v) => typeof v === "number" ? v.toString(): v, 4));
