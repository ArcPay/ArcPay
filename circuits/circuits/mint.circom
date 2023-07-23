pragma circom 2.1.5;

include "./node_modules/circomlib/circuits/comparators.circom";
include "./merkle_tree.circom";

// If the sender is the 0 address, the transaction is a mint request,
// if the recipient is 0, the transaction is a withdrawal, if neither are
// 0 it's an L2->L2 send, and both can't be 0.
template Mint(levels, mintLevels) {
    signal input step_in[2];
    signal input sender;
    signal input recipient;

    // merkle proof for mint tree
    signal input leaf_coins[2];
    signal input mintPathElements[mintLevels];
    signal input mintPathIndices[mintLevels];

    // merkle proof of state tree
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal output step_out[2];

    signal mint_root;
    signal initial_root;
    mint_root <== step_in[0];
    initial_root <== step_in[1];

    signal new_mint_root;
    signal new_root;

    // make sure it's a mint request by checking sender is zero and recipient is non-zero.
    sender === 0;
    signal is_recipient_zero <== IsZero()(in <== recipient);
    is_recipient_zero === 0;

    // make sure the mint transaction is included in mint_root
    signal mint_root_calculated <== CheckMerkleProof(mintLevels)(
        leaf <== Poseidon(3)(inputs <== [recipient, leaf_coins[0], leaf_coins[1]]),
        pathElements <== mintPathElements,
        pathIndices <== mintPathIndices
    );
    mint_root === mint_root_calculated;

    // since a leaf has been minted, replace it with 0 and update the merkle root of the mint tree.
    new_mint_root <== CheckMerkleProof(mintLevels)(
        leaf <== 0,
        pathElements <== mintPathElements,
        pathIndices <== mintPathIndices
    );

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

    step_out[0] <== new_mint_root;
    step_out[1] <== new_root;
}

// TODO: decide on the public inputs.
component main { public [step_in] } = Mint(3, 3);
