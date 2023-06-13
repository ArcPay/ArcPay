pragma circom 2.1.5;

include "../node_modules/circomlib/circuits/comparators.circom";

// Concatenates 3 arrays
template concat3(l1, l2, l3) {
    signal input a[l1];
    signal input b[l2];
    signal input c[l3];
    signal output out[l1 + l2 + l3];

    for (var i = 0; i < l1; i++) {
        out[i] <== a[i];
    }

    for (var i = 0; i < l2; i++) {
        out[l1 + i] <== b[i];
    }

    for (var i = 0; i < l3; i++) {
        out[l1 + l2 + i] <== c[i];
    }
}

template CoinRangesOverlap() {
    signal input a[2];
    signal input b[2];
    signal output out;

    signal b0_lte_a0 <== LessEqThan(128)([b[0], a[0]]);
    signal a0_lte_b1 <== LessEqThan(128)([a[0], b[1]]);
    signal a0_in_b <== b0_lte_a0 * a0_lte_b1;

    signal b0_lte_a1 <== LessEqThan(128)([b[0], a[1]]);
    signal a1_lte_b1 <== LessEqThan(128)([a[1], b[1]]);
    signal a1_in_b <==  b0_lte_a1 * a1_lte_b1;
    out <== OR()(a <== a0_in_b, b <== a1_in_b);
}
