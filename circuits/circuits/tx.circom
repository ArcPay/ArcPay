pragma circom 2.1.5;

include "./merkle_tree.circom";
include "./sig.circom";
include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

// This circuit handles the state transition function for ArcPay
// There are 3 transaction types: mint, send, and withdraw.

// Send and withdraw transactions can offchain or forced onchain. However, mint must be onchain because we need to verify that enough Eth/token was sent to the validium contract.
// Forceds transactions can noop, because malicious actors can attempt to move funds they don't own.

// TODO: add fee by having a second "highest_fee_coin" where [higest_coin_to_send + 1, highest_fee_coin] are sent to the operator. 
template Send(levels, coin_bits, address_bits, n, k) {
    // maximally compressed transaction details
    signal input highest_coin_to_send;
    signal input recipient;

    signal input msghash[k];
    signal input r[k];
    signal input s[k];
    signal input pubkey[2][k];

    // advice that operator is forced to provide to execute transaction
    signal input owner;
    signal input leaf_coins[2]; // sending [leaf_coins[0], highest_coin_to_send]
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal input refundPathElements[levels];
    signal input refundPathIndices[levels];
    
    signal input possible_next_forced_hash_chain;

    // state 
    signal input step_in[3];

    signal output step_out[3];

    signal state_root <== step_in[0];
    signal forced_hash_chain <== step_in[1];
    signal withdrawals_hash_chain <== step_in[2];

    // verify signature
    signal (is_sign_valid, sender) <== VerifySignature(4, n, k)(
        r <== r,
        s <== s,
        msghash <== msghash,
        pubkey <== pubkey,
        msg <== [highest_coin_to_send, recipient],
    );

    // See if it's an onchain transaction, unroll the forced_hash_chain if so
    // A forced transaction consists of a signature, a recipient, and highest_coin_to_send, the operator is forced to provide the remaining relevant information as advice.
    component unroller <== Keccak(
        32*8 + // previous accumulator value
        coin_bits + // highest coin to send
        address_bits + // recipient
        2 * n * k * 5, // signature details
        32 * 8 // next accumulator value
    );
    // TODO: unroller inputs
    signal calculated_forced_hash_chain <== Bits2Num(32 * 8)(in <== unroller.out);
    signal is_forced <== IsEqual()(in <== [calculated_forced_hash_chain, forced_hash_chain]);
    step_out[1] <== is_forced * (forced_hash_chain - possible_next_forced_hash_chain) + possible_next_forced_hash_chain; // unroll if this is a forced transaction


    // make sure it's not an offchain mint transaction
    // this confirms that any mint transaction made it through the onchain mint validation function which means
    // that the appropriate money was sent to the contract, and the leaf_coins range are the next availabe coins
    // in the validium, and leaf_coins == highest_coin_to_send
    // TODO: make sure the above checks exist
    signal is_mint <== IsEqual()(in <== [0, sender]);
    signal is_not_mint <== 1 - mint;
    signal is_forced_or_non_mint <== Or()(in <== [forced, is_not_mint]);
    is_forced_or_non_mint === 1;

    // require valid signature unless it's a mint TODO

    // use update and the highest_coin_in_validium if it's a mint TODO

    // The spent leaf should be owned by the sender, unless it's a mint transaction, in which case the leaf should be 0 TODO

    // To process a transaction we:
    // - Delete the old leaf
    // - Insert 2 new leaves
    //
    // We then output the new root from the circuit
    signal is_transition_valid <== Validate(levels)( // TODO: change this to "validate ownership", and account for a case where "highest_coin_to_send" is out of range
        initial_root <== initial_root,
        highest_coin_to_send <== highest_coin_to_send,
        signature <== signature,
        sender <== sender,
        owner <== owner,
        leaf_coins <== leaf_coins,
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );

    signal is_transaction_valid <== is_sign_valid * is_transition_valid;
    signal is_noop <== (1 - is_transaction_valid) * is_not_mint;
    
    signal new_state_root <== update_state(levels)(
        state_root <== state_root;
        old_leaf <== spent_leaf;
        pathElements <== pathElements;
        pathIndices <== pathIndices;
        leaf_coins[2] <== leaf_coins;
        highest_coin_to_send <== highest_coin_to_send;
        recipient <== recipient;
        sender <== sender;
        refundPathElements <== refundPathElements;
        refundPathIndices <== refundPathIndices;
    );

}

// Spends a leaf and updates the state root by sending some coins to the recipient, and refunding the
// remaining coins to the sender.
template update_state(levels) {
    // State details
    signal input state_root;
    signal input old_leaf;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    // Transaction details
    signal input leaf_coins[2];
    signal input highest_coin_to_send;
    signal input recipient;

    // Refund details in case there is change to be sent back
    signal input sender;
    signal input refundPathElements[levels];
    signal input refundPathIndices[levels];

    signal output new_root;

    // Send the coins to recipient by replacing the current leaf
    signal updated_state_root <== UpdateLeaf(levels)(
        old_leaf <== old_leaf;
        new_leaf <== Poseidon(3)(inputs <== [recipient, leaf_coins[0], highest_coin_to_send]);
        pathElements <== PathElements;
        pathIndices <== PathIndices;
        old_root <== 0;
    );

    // Refund the sender if necessary
    signal is_send_all <== IsEqual()(in <== [highest_coin_to_send, leaf_coins[1]]);
    signal refund_coin_leaf <== Poseidon(3)(inputs <== [sender, highest_coin_to_send+1, leaf_coins[1]]);
    signal refund_leaf <== (1 - is_send_all) * refund_coin_leaf; // If we don't need a refund, we'll just update a 0 leaf to 0 again

    new_root <== refunded_state_root <== UpdateLeaf(levels)(
        old_leaf <== 0;
        new_leaf <== refund_leaf;
        pathElements <== refundPathElements;
        pathIndices <== refundPathIndices;
        old_root <== updated_state_root;
    );
}

// Gets the owner of a given coin
// If the coin is outside the validium's range, the owner is the 0 address
template GetOwner(levels) {
    signal input state_root;
    signal input highest_coin_to_send;
    signal input max_coin;
    signal input owner_advice;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal output owner;

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

    // Validate the Merkle proof
    signal calculated_root <== CheckMerkleProof(levels)(
        leaf <== Poseidon(3)(inputs <== [owner_advice, leaf_coins[0], leaf_coins[1]]),
        pathElements <== pathElements,
        pathIndices <== pathIndices
    );
    signal is_owned <== IsEqual()(calculated_root, state_root);
    signal is_in_bounds <== LessEqThan(coin_bits)(in <== [highest_coin_to_send, max_coin]);

    // Force the operator to provide a valid ownership proof if the coin is in range
    // i.e., "if the coin is_in_bounds, is_owned must be true"
    is_in_bounds === is_owned;

    owner <== owner_advice * is_in_bounds;
}
