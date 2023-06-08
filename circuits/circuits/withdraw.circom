pragma circom 2.1.15;

include "./node_modules/circomlib/circuits/comparators.circom";


// Top level transaction handler
//
// If the sender is the 0 address, the transaction is a mint request,
// if the recipient is 0, the transaction is a withdrawal, if neither are
// 0 it's an L2->L2 send, and both can't be 0.
template Withdraw(levels) {
    signal input sender;
    signal input recipient;
    signal input initial_root;

    signal output new_root;

    // make sure it's a withdraw request by checking recipient is zero and sender is non-zero.
    recipient === 0;
    IsZero()(in <== sender) === 0;
}
