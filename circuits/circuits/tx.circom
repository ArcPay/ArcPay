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
    signal input recipient;
    signal input sent_coins[2];
    signal input signature;

    // altered state
    signal input owner;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal output new_root;

    // We noop when the transaction is invalid, which occurs when:
    // - The signature is invalid
    // - The coin range is out of order
    // - The coin range is out of bounds
    // - The signer doesn't own those coins

    signal signature_is_valid <== 0; // TODO

    // The coin range is invalid if it's out of order or out of bounds
    component coins_in_order LessThan(128);
    coins_in_order.in[0] <== sent_coins[0];
    coins_in_order.in[1] <== sent_coins[1];

    component coins_in_bounds LessEqThan(128);
    coins_in_bounds.in[0] <== sent_coins[1];
    coins_in_bounds.in[1] <== highest_coin;

    // Signals used in LessThan need to be range checked to avoid a subtle overflow bug demonstrated here https://github.com/BlakeMScurr/comparator-overflow
    // Note; users must *not* be allowed to force transactions where the coin values exceed 128 bits and therefore don't pass the range check,
    // or they'll be able to halt and break the system
    component coin_range_checks[3];
    for (var i = 0; i < 3; i++) {
        coin_range_checks[i] = Num2Bits(128);
    }
    coin_range_checks[0].in <== sent_coins[0];
    coin_range_checks[1].in <== sent_coins[1];
    coin_range_checks[2].in <== highest_coin;

    // If the sent coins are valid (i.e., in bounds and in order), then the operator must provide a merkle proof for *some* coins in that range.
    // Since adjacent coin ranges with the same owner are always consolidated, we know that if the sender truly owns all the coins in the sent range,
    // then merkle proof will specify a range owned by them that is a superset of the sent coins.
    signal signer_owns_coins <== 0; // TODO

    component transaction_is_valid = IsEqual();
    transaction_is_valid.in[0] <== signature_is_valid + coins_in_order.out + coins_in_bounds.out + signer_owns_coins;
    transaction_is_valid.in[1] <== 4;

    // To process a transaction we:
    // - Delete the old leaf
    // - Insert up to 3 new leaves
    // - Merge up to 3 adjacent new leaves
    // 
    // We then output the new root from the circuit

    signal next_root = 0; // TODO

    // If the transaction was valid output next_root, otherwise output the initial_root
    new_root <== (next_root - initial_root) * transaction_is_valid + initial_root;
}

template Mint() {
    // TODO: check incoming mint list
}

template Withdraw() {
    // TODO: check signature
}