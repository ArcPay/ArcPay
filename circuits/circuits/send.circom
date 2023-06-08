pragma circom 2.1.15;

include "merkle_tree.circom";
include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

template Send(levels) {
    signal input sender;
    signal input recipient;
    signal input initial_root;

    signal output new_root;

    // make sure it's a send request by checking sender and recipient is non-zero
    IsZero(in <== sender) === 0;
    IsZero(in <== recipient) === 0;

    // To process a transaction we:
    // - Delete the old leaf
    // - Insert up to 3 new leaves
    // - Merge up to 3 adjacent new leaves
    //
    // We then output the new root from the circuit
    component transaction_is_valid = Validate();

    signal next_root = 0; // TODO

    // If the transaction was valid output next_root, otherwise output the initial_root
    new_root <== (next_root - initial_root) * transaction_is_valid.out + initial_root;
}

// A send transaction is invalid if:
// - The signature is invalid, or;
// - The coin range is out of order, or;
// - The coin range is out of bounds, or;
// - The signer doesn't own the coins they're trying to send
template Validate() {
    // public inputs
    signal initial_root;
    signal highest_coin;

    // private inputs
    // tx
    signal input recipient;
    signal input sent_coins[2];
    signal input signature;

    // relevant state
    signal input owner;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal output send_is_valid;

    signal signature_is_valid <== 0; // TODO
    signal signer <== 0; // TODO: recover signer from signature, or just pass it in as input

    // The coin range is invalid if it's out of order or out of bounds
    component coins_in_order LessThan(128);
    coins_in_order.in[0] <== sent_coins[0];
    coins_in_order.in[1] <== sent_coins[1];

    component coins_in_bounds LessEqThan(128);
    coins_in_bounds.in[0] <== sent_coins[1];
    coins_in_bounds.in[1] <== highest_coin;

    // Signals used in LessThan need to be range checked to avoid a subtle overflow bug demonstrated here https://github.com/BlakeMScurr/comparator-overflow
    // Note; users must *not* be allowed to force transactions where the coin values exceed 128 bits and therefore don't pass the range check,
    // or they'll be able to halt and break the system. TODO: ensure this is enforced by the smart contracts
    component coin_range_checks[5];
    for (var i = 0; i < 5; i++) {
        coin_range_checks[i] = Num2Bits(128);
    }
    coin_range_checks[0].in <== sent_coins[0];
    coin_range_checks[1].in <== sent_coins[1];
    coin_range_checks[2].in <== highest_coin;
    coin_range_checks[3].in <== leaf_coins[0];
    coin_range_checks[4].in <== leaf_coins[1];

    // If the sent coins are valid (i.e., in bounds and in order), then the operator must provide a merkle proof for *some* coins in that range.
    // Since adjacent coin ranges with the same owner are always consolidated, we know that if the sender truly owns all the coins in the sent range,
    // then the leaf coins will owned by them and will be a superset of the spent range.

    // Validate the Merkle proof
    component leaf = Poseidon(3);
    leaf.in[0] <== owner;
    leaf.in[1] <== leaf_coins[0];
    leaf.in[2] <== leaf_coins[1];

    component merkle_proof_checker CheckMerkleProof(levels);
    merkle_proof_checker.leaf <== leaf;
    for (var i = 0; i < levels; i++) {
        merkle_proof_checker.pathElements[i] <== pathElements[i];
        merkle_proof_checker.pathIndices[i] <== pathIndices[i];
    }
    merkle_proof_checker.root === initial_root;

    // Require overlap between leaf coins and sent coins, if the sent coins are valid
    component coin_ranges_overlap = CoinRangesOverlap();
    for (var i = 0; i < 2; i++) {
        coin_ranges_overlap.a[i] <== leaf_coins[i];
        coin_ranges_overlap.b[i] <== sent_coins[i];
    }
    (1 - coin_ranges_overlap.out) * sent_coins_valid === 0; // If the sent coins are valid, the sent coins and leaf coins have to overlap

    // Check that the leaf coins are owned by the signer and contain the sent coins
    component leaf_cointains_sent = CoinRangeContains();
    for (var i = 0; i < 2; i++) {
        leaf_cointains_sent.superset[i] <== leaf_coins[i];
        leaf_cointains_sent.subset[i] <== sent_coins[i];
    }

    component signer_is_owner = IsEqual();
    signer_is_owner.in[0] <== signer;
    signer_is_owner.in[1] <== owner;

    // Check if all conditions for transaction validity hold
    component transaction_is_valid = MultiAND(5);
    transaction_is_valid.in[0] <== signature_is_valid;
    transaction_is_valid.in[1] <== coins_in_order.out;
    transaction_is_valid.in[2] <== coins_in_bounds.out;
    transaction_is_valid.in[3] <== leaf_contains_sent.out;
    transaction_is_valid.in[4] <== signer_is_owner.out;

    send_is_valid <== transaction_is_valid.out;
}

// Checks whether one coin range contains another
// I.e., [10, 20] contains [10, 20], [11, 20], and [15, 15] but doesn't contain
// [1, 5], [5, 11], [9, 11], or [15, 21]
template CoinRangeContains() {
    signal input superset[2];
    signal input subset[2];
    signal output contains;

    component check_low = LessEqThan(128);
    check_low[0].in <== superset[0];
    check_low[1].in <== subset[0];

    component check_high = GreaterEqThan(128);
    check_high[0].in <== superset[1];
    check_high[1].in <== subset[1];

    contains <== check_low.out * check_high.out;
}

// Checks whether two coin ranges overlap
// I.e, [1, 10] overlaps with [5, 10], [5, 15], and [10, 20], but doesn't overlap
// with [11, 20] or [20, 50]
template CoinRangesOverlap() {
    signal input a[2];
    signal input b[2];
    signal output out;

    // If the two ranges overlap, then the higher of the two lower bounds will be in both ranges
    signal common_coin <-- a[0] > b[0] ? a[0] : b[0];
    component overlap_checks[4];
    for (var i = 0; i < 4; i++) {
        overlap_checks[i] = LessEqThan(128);
    }

    // Verifies that the common coin is in the first range
    overlap_checks[0].in[0] <== a[0];
    overlap_checks[0].in[1] <== common_coin;
    overlap_checks[1].in[0] <== common_coin;
    overlap_checks[1].in[1] <== a[1];

    // Verifies that the common coin is in the second range
    overlap_checks[2].in[0] <== b[0];
    overlap_checks[2].in[1] <== common_coin;
    overlap_checks[3].in[0] <== common_coin;
    overlap_checks[3].in[1] <== b[1];

    component ranges_overlap = MultiAND(4);
    for (var i = 0; i < 4; i++) {
        ranges_overlap[i] <== overlap_checks[i];
    }

    out <== ranges_overlap.out;
}

// Assumes boolean inputs
template MultiAND(n) {
    signal input in[n];
    signal output out;

    let sum = 0;
    for (var i = 0; i < n; i++) {
        sum += in[i];
    }

    component sumcheck = IsEqual();
    sumcheck.in[0] <== sum;
    sumcheck.in[1] <== n;
    out <== sumcheck.out;
}

template EditTree() {}
