pragma circom 2.1.5;

include "./node_modules/circomlib/circuits/comparators.circom";
include "./merkle_tree.circom";

// If the sender is the 0 address, the transaction is a mint request,
// if the recipient is 0, the transaction is a withdrawal, if neither are
// 0 it's an L2->L2 send, and both can't be 0.
template Withdraw(levels) {
    signal input sender;
    signal input recipient;
    signal input initial_root;

    signal output new_root;

    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    // make sure it's a withdraw request by checking recipient is zero and sender is non-zero.
    recipient === 0;
    signal is_sender_zero <== IsZero()(in <== sender);
    is_sender_zero === 0;

    // verify that the coins are included in the current merkle root.
    signal initial_root_calculated <== CheckMerkleProof(levels)(
        leaf <== Poseidon(3)(inputs <== [sender, leaf_coins[0], leaf_coins[1]]),
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );
    initial_root === initial_root_calculated;

    // delete the leaf and compute the new root.
    new_root <== CheckMerkleProof(levels)(
        leaf <== 0,
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );
}

component main { public [initial_root] } = Withdraw(3);
