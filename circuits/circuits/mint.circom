pragma circom 2.1.5;

include "./node_modules/circomlib/circuits/comparators.circom";
include "./merkle_tree.circom";

template Mint(levels) {
    signal input initial_root;
    signal input sender;
    signal input recipient;

    signal input leaf_coins[2];

    // merkle proof of state tree
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal output new_root;

    // update the state tree by adding leaf to initial_root resulting in new_root.
    signal initial_root_calculated <== CheckMerkleProof(levels)(
        leaf <== 0,
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );
    initial_root_calculated === initial_root;
    new_root <== CheckMerkleProof(levels)(
        leaf <== Poseidon(3)(inputs <== [recipient, leaf_coins[0], leaf_coins[1]]),
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );
}