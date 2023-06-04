pragma circom 2.0.2;

include "merkle_tree.circom";
include "./node_modules/circomlib/circuits/comparators.circom";


// Top level transaction handler
// 
// If the sender is the 0 address, the transaction is a mint request,
// if the recipient is 0, the transaction is a withdrawal, if neither are
// 0 it's an L2->L2 send, and both can't be 0.
template HandleTransaction() {
    signal input sender;
    signal input recipient;
    signal input initial_root;

    signal output new_root;

    component is_mint = IsZero();
    is_mint.in <== sender;

    component is_withdrawal = IsZero();
    is_withdrawal.in <== recipient;

    // Make sure that at least one address is non-zero
    is_mint.out * is_withdrawal.out === 0;

    component mint = Mint(); // TODO: set inputs
    component withdrawal = Withdraw(); // TODO: set inputs
    component send = Send(); // TODO: set inputs

    // Set the new root based on the transaction type
    // By default the new root is send's output, but this is overridden if the transaction was a mint or withdrawal
    signal intermediate_root <== (mint.new_root - send.new_root) * is_mint.out + send.new_root;
    signal new_root <== (withdrawal.new_root - intermediate_root) * is_withdrawal.out + intermediate_root;
}

template Send() {
    // public inputs
    signal initial_root;
    signal highest_coin;

    // private inputs
    // tx
    signal input sender;
    signal input recipient;
    signal input sent_coins[2];
    signal input signature;

    // state
    signal input owner;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

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
    new_root <== (next_root - initial_root) * transaction_is_valid  + initial_root;
}

template Mint() {
    // TODO: check incoming mint list
}

template Withdraw() {
    // TODO: check signature
}