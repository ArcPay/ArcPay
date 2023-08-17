template Transaction(levels, n, k) {
    signal input step_in[5];
    signal initial_state_root <== step_in[0];
    signal withdrawal_bit_chain <== step_in[1];
    signal withdrawal_tree <== step_in[2];
    signal withdrawal_amount <== step_in[3];
    signal forced_chain <== step_in[4];

    signal input sender;
    signal input recipient;

    signal input owner;
    signal input leaf_coins[2];
    signal input pathElements[levels];
    signal input pathIndices[levels];

    signal input highest_coin_to_send;

    signal input pathElementsForZero[levels];
    signal input pathIndicesForZero[levels];

    signal input r[k];
    signal input s[k];
    signal input msghash[k];
    signal input pubkey[2][k];

    signal input new_forced_chain_advice;

    signal output new_state_root;
    signal output new_withdrawal_bit_chain;
    signal output new_withdrawal_tree;
    signal output new_withdrawal_amount;
    signal output new_forced_chain;

    // Determine the transaction type
    {
    signal is_mint <== IsZero()(in <== sender);
    signal is_withdrawal <== IsZero()(in <== recipient);
    }

    // Can't be both mint and withdrawal
    {
        signal is_meaningful_tx_type <== Or([is_mint, is_withdrawal]);
        is_meaningful_tx_type === 1; // NB SCD: the contract must not allow forced transactions where the sender and recipient are 0
    }

    // Determine whether the transaction was forced on-chain
    signal is_forced;
    {
        signal tx_hash <== Poseidon(4)(inputs <== [leaf_coins[0], leaf_coins[1], highest_coin_to_send, recipient]);
        is_forced <== IsEqual()(in <== [
            forced_chain,
            Poseidon(2)(inputs <== [tx_hash, new_forced_chain_advice]),
        ]);

        new_forced_chain <== (forced_chain - new_forced_chain_advice) * is_forced + new_forced_chain_advice; // unroll forced tx chain if applicable
    }

    // Withdrawals must be forced on-chain
    {
        signal is_offchain_withdrawal <== And()(
            a <== is_withdrawal,
            b <== Not()(in <== is_forced),
        )
        is_offchain_withdrawal === 0;
    }

    // signature verification.
    signal is_sign_valid <== VerifySignature(4, n, k)(
        r <== r,
        s <== s,
        msghash <== msghash,
        pubkey <== pubkey,
        msg <== [leaf_coins[0], leaf_coins[1], highest_coin_to_send, recipient],
        signer <== sender
    );

    // Transactions need signatures if they are unforced
    signal is_unforced_and_unsigned = And()(
        a <== Not()(in <== is_forced),
        b <== Not()(in <== is_sign_valid),
    );
    is_unforced_and_unsigned === 0;


    // Withdrawals must add to the withdrawal output accumulator
    
}