pragma circom 2.1.5;

include "./merkle_tree.circom";
include "./sig.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

// To offload most of the costs onto the user, the withdraw algorithm outputs a Merkle tree
// that user's can withdraw from on-chain.
// These users need to be able to calculate their Merkle proofs from fully on-chain data, so only withdrawals that were posted on-chain should be processed.
// Also, there is no way for users or the smart contract to determine whether withdrawals are invalid or not,
// and the validity of the withdrawals will alter the value of the Merkle tree.
// There are 2^n possible Merkle roots for n withdrawals of unknown validity, so it quickly becomes infeasible for users to guess
// their Merkle proofs unless they're given extra advice by the operator.
// 
// It's important to minimise the advice the operator has to give, because the smart contract will force the operator to give all the necessary
// advice when the operator calls the state transition function. There is a gas cost for posting advice, and we need to make sure that attackers can't cheaply
// force a cost on the operator, and even more importantly, we need to make sure that the operator can post all the advice within the gas block limit.
// The minimal advice the operator can give is an n-bit string where each bit indicates whether a given withdrawal was valid or not.

// Since there is a potentially unbounded number of withdrawal requests, and field elements are limited to ~254 bits, we hash substrings together
// into a hash chain and unroll it in the smart contract.
// The initial implementation has one bit per field element for algorithmic simplicity. TODO: make it a fully dense bitstring.
// TODO: it should be possible to unroll the advice string *before* posting the state transition so that we don't hit the gas block limit.
// TODO: the output *should* be a keccak Merkle tree with minimised depth to save gas
template Withdraw(levels) {
    signal input is_withdrawal;
    signal input is_valid_transaction;

    signal input recipient;
    signal input amount;

    signal input withdrawalPathElements[levels];
    signal input withdrawalPathIndices[levels];

    signal input bit_chain;
    signal input root;
    signal input total_amount;
    signal input valid_withdrawal_count;

    signal output new_bit_chain;
    signal output new_root;
    signal output new_total_amount;
    signal output new_valid_withdrawal_count;

    // Calculate what the outputs would be if it's a withdrawal
    signal calculated_bit_chain <== Poseidon(2)(inputs <== [bit_chain, is_valid_transaction]);
    signal updated_root <== UpdateLeaf(levels)(
        old_leaf <== 0,
        new_leaf <== Poseidon(2)(inputs <== [recipient, amount]),
        pathElements <== withdrawalPathElements,
        pathIndices <== withdrawalPathIndices,
        old_root <== root
    );
    signal calculated_root <== (updated_root - root) * is_valid_transaction + root;
    signal calculated_total_amount <== total_amount + (amount * is_valid_transaction);
    signal calculated_valid_withdrawal_count <== valid_withdrawal_count + is_valid_transaction;

    // Only update the outputs if it's a withdrawal
    new_bit_chain <== (calculated_bit_chain - bit_chain) * is_withdrawal + bit_chain;
    new_root <== (calculated_root - root) * is_withdrawal + root;
    new_total_amount <== (calculated_total_amount - total_amount) * is_withdrawal + total_amount;
    new_valid_withdrawal_count <== (calculated_valid_withdrawal_count - valid_withdrawal_count) * is_withdrawal + valid_withdrawal_count;
}
