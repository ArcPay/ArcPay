pragma circom 2.1.5;

include "./sig.circom";
include "./mint.circom";
include "./send.circom";
include "./withdraw.circom";
include "./node_modules/circomlib/circuits/poseidon.circom";
include "./node_modules/circomlib/circuits/gates.circom";

template Transaction(levels, withdraw_levels, n, k) {
    signal input step_in[6];
    signal initial_state_root <== step_in[0];
    signal withdrawal_bit_chain <== step_in[1];
    signal withdrawal_root <== step_in[2];
    signal withdrawal_amount <== step_in[3];
    signal valid_withdrawal_count <== step_in[5];
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

    signal input withdrawalPathElements[levels];
    signal input withdrawalPathIndices[levels];

    signal input new_forced_chain_advice;

    signal output new_state_root;
    signal output new_withdrawal_bit_chain;
    signal output new_withdrawal_root;
    signal output new_withdrawal_amount;
    signal output new_valid_withdrawal_count;
    signal output new_forced_chain;

    // Determine the transaction type
    signal is_mint <== IsZero()(in <== sender);
    signal is_withdrawal <== IsZero()(in <== recipient);

    // Can't be both mint and withdrawal
    {
        signal is_meaningful_tx_type <== OR()(a <== is_mint, b <== is_withdrawal);
        is_meaningful_tx_type === 1; // NB SCD: the contract must not allow forced transactions where the sender and recipient are 0
    }

    // Determine whether the transaction was forced on-chain
    signal is_forced;
    {
        signal tx_hash <== Poseidon(4)(inputs <== [leaf_coins[0], leaf_coins[1], highest_coin_to_send, recipient]);
        signal forced_chain_calculated <== Poseidon(2)(inputs <== [tx_hash, new_forced_chain_advice]);
        is_forced <== IsEqual()(in <== [
            forced_chain,
            forced_chain_calculated
        ]);

        new_forced_chain <== (forced_chain - new_forced_chain_advice) * is_forced + new_forced_chain_advice; // unroll forced tx chain if applicable
    }

    // Withdrawals must be forced on-chain
    {
        signal is_offchain_withdrawal <== AND()(
            a <== is_withdrawal,
            b <== NOT()(in <== is_forced)
        );
        is_offchain_withdrawal === 0;
    }

    // signature verification.
    signal is_sign_valid <== VerifySignature(4, n, k)(
        r <== r,
        s <== s,
        msghash <== msghash,
        pubkey <== pubkey,
        signer <== sender,
        msg <== [leaf_coins[0], leaf_coins[1], highest_coin_to_send, recipient]
    );

    // Transactions need signatures if they are unforced
    signal is_unforced_and_unsigned <== AND()(
        a <== NOT()(in <== is_forced),
        b <== NOT()(in <== is_sign_valid)
    );
    is_unforced_and_unsigned === 0;

    // Calculate the new state root if the transaction were a mint
    signal post_mint_root <== Mint(levels) (
        initial_root <== initial_state_root,
        sender <== sender,
        recipient <== recipient,
        leaf_coins <== leaf_coins,
        pathElements <== pathElements,
        pathIndices <== pathElements
    );

    // Calculate the new state if the transaction were a send or withdraw
    signal (is_valid_send, post_send_root) <== Send(levels, n, k) (
        initial_root <== initial_state_root,
        sender <== sender,
        recipient <== recipient,
        owner <== owner,
        leaf_coins <== leaf_coins,
        pathElements <== pathElements,
        pathIndices <== pathIndices,
        highest_coin_to_send <== highest_coin_to_send,
        pathElementsForZero <== pathElementsForZero,
        pathIndicesForZero <== pathIndicesForZero
    );

    // Withdrawals must add to the withdrawal output accumulator
    signal (t1, t2, t3, t4) <== Withdraw(withdraw_levels)(
        is_withdrawal <== is_withdrawal,
        is_valid_transaction <== is_valid_send,
        recipient <== recipient,
        amount <== highest_coin_to_send - leaf_coins[0],
        withdrawalPathElements <== withdrawalPathElements,
        withdrawalPathIndices <== withdrawalPathIndices,
        bit_chain <== withdrawal_bit_chain,
        root <== withdrawal_root,
        total_amount <== withdrawal_amount,
        valid_withdrawal_count <== valid_withdrawal_count
    );
    new_withdrawal_bit_chain <== t1;
    new_withdrawal_root <== t2;
    new_withdrawal_amount <== t3;
    new_valid_withdrawal_count <== t4;

    // Calculate the new root depending on the transaction type
    new_state_root <== (post_mint_root - post_send_root) * is_mint + post_send_root;
}