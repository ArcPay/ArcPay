pragma circom 2.1.5;

include "./git_modules/circom-ecdsa/circuits/ecdsa.circom";
include "./git_modules/circom-ecdsa/circuits/zk-identity/eth.circom";
include "./node_modules/circomlib/circuits/gates.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

// TODO: do we need to check that all registers of r,s fit in n bits?
// Note: The n-bit check is done for pubkey in FlattenPubkey circuit.
template VerifySignature(hashIns, n, k) {
    signal input r[k];
    signal input s[k];
    signal input msghash[k];
    signal input pubkey[2][k];
    signal input signer;

    signal input msg[hashIns];

    signal output is_valid;

    // message hash check
    {
        signal msghash_computed <== Poseidon(hashIns)(inputs <== msg);

        var cumulativeM = 0;
        var nPow = 1;
        for (var i=0; i<k; i++) {
            _ <== Num2Bits(n)(in <== msghash[i]);
            cumulativeM += msghash[i]*nPow;
            nPow *= 2**n;
        }

        cumulativeM === msghash_computed;
    }

    signal is_valid_signature <== ECDSAVerifyNoPubkeyCheck(n,k)(
        r <== r,
        s <== s,
        msghash <== msghash,
        pubkey <== pubkey
    );

    signal actual_signer <== PubkeyToAddress()(
        pubkeyBits <== FlattenPubkey(n, k)(chunkedPubkey <== pubkey)
    );

    signal puported_signer_is_signer <== IsEqual()(inputs <== [signer, actual_signer]);
    is_valid <== AND()(a <== is_valid_signature, b <== puported_signer_is_signer);
}
