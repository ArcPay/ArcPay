pragma circom 2.0.2;

include "merkle_tree.circom";
include "./node_modules/circomlib/circuits/comparators.circom";


template handle_transaction() {
    // TODO: branch on whether to send, mint, or withdraw
}

template send() {
    // public inputs
    signal initial_root;
    signal highest_coin;

    // private inputs
    signal input sender;
    signal input recipient;
    signal input start_coin;
    signal input end_coin;

    signal input leaf;
    signal input pathElements[levels];
    signal input pathIndices[levels];
    signal input signature;

    signal output new_root;

    // We noop when the transaction is invalid, which occurs when:
    // - The signature is invalid
    // - The signer isn't the sender
    // - The sender isn't the recipient
    // - The merkle proof falis
    // - The leaf doesn't contain the coin range
    // - The sender doesn't own the coins

    signal signature_is_valid <== 0; // TODO
    signal signer_is_sender <== 0; // TODO
    signal sender_is_not_recipient <== 0; // TODO
    signal merkle_proof_is_valid <== 0; // TODO
    signal leaf_cointains_coins <== 0; // TODO
    signal sender_owns_coins <== 0; // TODO

    component transaction_is_valid = IsEqual();
    transaction_is_valid.in[0] <== signature_is_valid + signer_is_sender + merkle_proof_is_valid + leaf_cointains_coins + sender_owns_coins;
    transaction_is_valid.in[1] <== 6;

    // To process a transaction we:
    // - Delete the old leaf
    // - Insert up to 3 new leaves
    // - Merge up to 3 adjacent new leaves
    // 
    // We then output the new root from the circuit

    signal next_root = 0; // TODO

    // If the transaction was valid output next_root, otherwise output the initial_root
    (next_root - initial_root) * transaction_is_valid  + initial_root === new_root;
}

template mint() {
    // TODO: check incoming mint list
}

template withdraw() {
    // TODO: check signature
}