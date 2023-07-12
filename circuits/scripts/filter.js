import { expect }  from 'chai';
import { default as vmtree } from 'vmtree-sdk';
import { MerkleTree, stringify_nova_json, verifyMerkleProof } from './util.js';
import { ethers } from "ethers";

// Generates and validates the input data for the filter circuit
// 1) Generate mock onchain data:
//      a. We construct a state history
//      b. We take a set of claims and keccak them together into a hash chain, remembering all intermediate values
// 2) Build inputs
//      a. Initialise a filtered tree
//      b. We unwind the hash chain:
//          i/ Add to the filtered tree if claim exists in history
//          ii/ Set inputs


// Construct state history
const historyTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });
const stateTree1 = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });
const stateTree2 = new MerkleTree({ hasher: vmtree.poseidon, levels: 3, zero: 0 });

const addresses = [
    1234,
    5678,
    9101,
]

stateTree1.insert(0, vmtree.poseidon([addresses[0], 0, 10]))
stateTree1.insert(1, vmtree.poseidon([addresses[1], 11, 15]))
stateTree1.insert(2, vmtree.poseidon([addresses[2], 16, 20]))

stateTree2.insert(0, vmtree.poseidon([addresses[0], 0, 10])) // all coins have moved to the first user
stateTree2.insert(1, vmtree.poseidon([addresses[0], 11, 15]))
stateTree2.insert(2, vmtree.poseidon([addresses[0], 16, 20]))

historyTree.insert(0, stateTree1)
historyTree.insert(1, stateTree2)

// construct claims
const claims = [
    
]

console.log(ethers.keccak256("0x12"))
