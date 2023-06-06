pragma circom 2.1.5;

include "./merkle_tree.circom";
include "./sig.circom";
include "./efficient_ecdsa/circom-ecdsa-circuits/ecdsa.circom";
include "./efficient_ecdsa/circom-ecdsa-circuits/zk-identity/eth.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

// If the sender is the 0 address, the transaction is a mint request,
// if the recipient is 0, the transaction is a withdrawal, if neither are
// 0 it's an L2->L2 send, and both can't be 0.
template Withdraw(levels, n, k) {
    signal input sender;
    signal input recipient;
    signal input initial_root;

    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal output new_root;

    // signature verification.
    {
        signal input r[k];
        signal input s[k];
        signal input msghash[k];
        signal input pubkey[2][k];
        // signature verification.
        VerifySignature(n, k)(
            r <== r,
            s <== s,
            msghash <== msghash,
            pubkey <== pubkey,
            leaf_coins <== leaf_coins,
            receiver <== recipient,
            signer <== sender
        );
    }

    {
        // make sure it's a withdraw request by checking recipient is zero and sender is non-zero.
        recipient === 0;
        signal is_sender_zero <== IsZero()(in <== sender);
        is_sender_zero === 0;
    }

    // verify that the coins are included in the current merkle root.
    signal initial_root_calculated <== CheckMerkleProof(levels)(
        leaf <== Poseidon(3)(inputs <== [sender, leaf_coins[0], leaf_coins[1]]),
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );

    signal is_roots_equal <== IsEqual()(in <== [initial_root, initial_root_calculated]);

    // transfer the ownership of the withdrawn coins to zero address and compute the new root.
    signal root_with_deleted_leaf <== CheckMerkleProof(levels)(
        leaf <== Poseidon(3)(inputs <== [0, leaf_coins[0], leaf_coins[1]]),
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );

    new_root <== initial_root + is_roots_equal*(root_with_deleted_leaf - initial_root);
}

// TODO: decide on the public inputs.
component main { public [initial_root] } = Withdraw(3, 64, 4);
