pragma circom 2.1.5;

include "merkle_tree.circom";
include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

template Send(levels) {
    signal input sender;
    signal input recipient;
    signal input initial_root;

    signal input owner;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal input highest_coin_to_send; // sending [leaf_coins[0], highest_coin_to_send]
    signal input signature;

    signal input pathElementsForZero[levels];
    signal input pathIndicesForZero[levels];

    signal output new_root;

    // make sure it's a send request by checking sender and recipient is non-zero
    {
        signal is_sender_zero <== IsZero()(in <== sender);
        is_sender_zero === 0;
        signal is_recipient_zero <== IsZero()(in <== recipient);
        is_recipient_zero === 0;
    }

    // To process a transaction we:
    // - Delete the old leaf
    // - Insert 2 new leaves
    //
    // We then output the new root from the circuit
    signal is_transaction_valid <== Validate(levels)(
        initial_root <== initial_root,
        highest_coin_to_send <== highest_coin_to_send,
        signature <== signature,
        sender <== sender,
        owner <== owner,
        leaf_coins <== leaf_coins,
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );

    // determine the new leaf corresponding to sender.
    // If sending all coins, we replace it with 0; otherwise we replace it with the remaining coins.
    signal is_send_all <== IsEqual()(in <== [highest_coin_to_send, leaf_coins[1]]);
    signal sender_coin_leaf <== Poseidon(3)(inputs <== [sender, highest_coin_to_send+1, leaf_coins[1]]);
    signal sender_leaf <== (1 - is_send_all) * sender_coin_leaf;

    signal send_root <== CheckMerkleProof(levels)(
        leaf <== sender_leaf,
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );

    // insert the leaf for recipient.
    // To do that, verify if the zero leaf is included in the new root with updated sender leaf.
    // Then insert recipient leaf.
    signal send_root_calculated <== CheckMerkleProof(levels)(
        leaf <== 0,
        pathElements <== pathElementsForZero,
        pathIndices <== pathIndicesForZero
    );
    send_root_calculated === send_root;

    signal receive_root <== CheckMerkleProof(levels)(
        leaf <== Poseidon(3)(inputs <== [recipient, leaf_coins[0], highest_coin_to_send]),
        pathElements <== pathElementsForZero,
        pathIndices <== pathIndicesForZero
    );

    // If the transaction was valid output next_root, otherwise output the initial_root
    new_root <== (receive_root - initial_root) * is_transaction_valid + initial_root;
}

// A send transaction is invalid if:
// - The signature is invalid, or;
// - The coin range is out of order, or;
// - The coin range is out of bounds, or;
// - The signer doesn't own the coins they're trying to send
template Validate(levels) {
    // public inputs
    signal input initial_root;

    // private inputs
    // tx
    signal input highest_coin_to_send; // sending [leaf_coins[0], highest_coin_to_send]
    signal input signature;
    signal input sender; // sender is also the signer.

    // relevant state
    signal input owner;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];


    signal output is_send_valid;

    signal is_signature_valid === 1; // TODO: ensure in smart contract's force_include() fn that signature is valid, otherwise revert.

    {
        // Signals used in LessThan need to be range checked to avoid a subtle overflow bug demonstrated here https://github.com/BlakeMScurr/comparator-overflow
        // Note; users must *not* be allowed to force transactions where the coin values exceed 128 bits and therefore don't pass the range check,
        // or they'll be able to halt and break the system. TODO: ensure this is enforced by the smart contracts
        // highest_coin_to_send is enforced to fit in 128 bits in smart contract.
        component coin_range_checks[2];
        for (var i = 0; i < 2; i++) {
            coin_range_checks[i] = Num2Bits(128);
        }
        coin_range_checks[0].in <== leaf_coins[0];
        coin_range_checks[1].in <== leaf_coins[1];
    }

    // If the sent coins are valid (i.e., in bounds and in order), then the operator must provide a merkle proof for *some* coins in that range.
    // Since adjacent coin ranges with the same owner are always consolidated, we know that if the sender truly owns all the coins in the sent range,
    // then the leaf coins will owned by them and will be a superset of the spent range.

    {
        // Validate the Merkle proof
        signal initial_root_calculated <== CheckMerkleProof(levels)(
            leaf <== Poseidon(3)(inputs <== [owner, leaf_coins[0], leaf_coins[1]]),
            pathElements <== pathElements,
            pathIndices <== pathIndices
        );
        initial_root_calculated === initial_root;
    }

    // Check that the leaf coins are owned by the signer and contain the sent coins
    CoinRangeContains()(
        set <== leaf_coins,
        element <== highest_coin_to_send
    );

    is_send_valid <== IsEqual()(in <== [sender, owner]);
}

// Checks whether an element is in a set.
// I.e., [10, 20] contains 10, 11, 20 but doesn't contain 8, 9, 21.
// Assumes that all inputs fit in 128 bits.
template CoinRangeContains() {
    signal input set[2];
    signal input element;

    signal is_low <== LessEqThan(128)(in <== [set[0], element]);
    signal is_high <== LessEqThan(128)(in <== [element, set[1]]);

    is_low * is_high === 1;
}

// Assumes boolean inputs
/*
template MultiAND(n) {
    signal input in[n];
    signal output out;

    var sum = 0;
    for (var i = 0; i < n; i++) {
        sum += in[i];
    }

    out <== IsEqual()(in <== [sum, n]);
}
*/

// TODO: decide on the public inputs.
component main = Send(3);
