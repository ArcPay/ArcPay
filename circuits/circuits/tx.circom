pragma circom 2.0.2;

include "./node_modules/circomlib/circuits/comparators.circom";


// Top level transaction handler
// 
// If the sender is the 0 address, the transaction is a mint request,
// if the recipient is 0, the transaction is a withdrawal, if neither are
// 0 it's an L2->L2 send, and both can't be 0.
template HandleTransaction(levels) {
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

    component mint = Mint(levels); // TODO: set inputs
    component withdrawal = Withdraw(levels); // TODO: set inputs
    component send = Send(levels); // TODO: set inputs

    // Set the new root based on the transaction type
    // By default the new root is send's output, but this is overridden if the transaction was a mint or withdrawal
    signal intermediate_root <== (mint.new_root - send.new_root) * is_mint.out + send.new_root;
    signal new_root <== (withdrawal.new_root - intermediate_root) * is_withdrawal.out + intermediate_root;
}

template Mint(levels) {
    // TODO: check incoming mint list
}

template Withdraw(levels) {
    // TODO: check signature
}