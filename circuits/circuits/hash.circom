pragma circom 2.0.2;

include "./node_modules/circomlib/circuits/poseidon.circom";

template HashLeftRight() {
    signal input left;
    signal input right;
    signal output hash;

    component poseidon = Poseidon(2);
    poseidon.inputs[0] <== left;
    poseidon.inputs[1] <== right;
    hash <== poseidon.out;
}

component main {
    public [ left, right ]
} = HashLeftRight();