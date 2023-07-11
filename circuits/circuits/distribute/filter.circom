pragma circom 2.1.5;

include "../git_modules/circom-ecdsa/circuits/vocdoni-keccak/keccak.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../merkle_tree.circom";

template Filter(coin_bits, history_depth, state_depth, filtered_depth, field_size) {
    // public inputs
    signal input step_in[5];
    signal claim_chain[2]; // The keccak hash chain accumulator of all claims to be processed, split across two 128 bit registers
    claim_chain[0] <== step_in[0];
    claim_chain[1] <== step_in[1];
    signal filtered_root <== step_in[2]; // The root of the poseidon merkle tree of the filtered claims
    signal filtered_count <== step_in[3]; // The number of elements in the filtered tree
    signal history_root <== step_in[4]; // The root of the history of all states of the validium

    signal output step_out[5];

    // private inputs
    signal input next_claim_chain[2];
    signal input history_pathElements[history_depth];
    signal input state_root;
    signal input filtered_pathElements[filtered_depth];
    
    // claim
    signal input address; // 160 bits
    signal input first_coin; // coin_bits bits
    signal input last_coin; // coin_bits bits
    signal input block_number; // history_depth bits
    signal input state_pathElements[state_depth]; // state_depth field elements
    signal input state_pathIndex; // state_depth bits

    // Unwind the keccak chain
    // The keccak chain has the form H(a_n, H(a_n-1, H(a_n-2, ...))). The first argument to H is a full claim, and the second is the previous value, and the base case is 0.
    // We unwind it from the outside and return the previous accumulator.
    component keccak = Keccak(
        160 + 2 * coin_bits + history_depth + state_depth * field_size + state_depth + 256,
        256
    );
    keccak.in <== concat8(160, coin_bits, coin_bits, history_depth, state_depth * field_size, state_depth, 128, 128)(
        Num2Bits(160)(in <== address),
        Num2Bits(coin_bits)(first_coin),
        Num2Bits(coin_bits)(last_coin),
        Num2Bits(history_depth)(block_number),
        MultiNum2Bits(state_depth, field_size)(state_pathElements),
        Num2Bits(state_depth)(state_pathIndex),
        Num2Bits(128)(next_claim_chain[0]),
        Num2Bits(128)(next_claim_chain[1])
    );

    signal claim_chain_bits[256] <== MultiNum2Bits(2, 128)(in <== claim_chain);
    for (var i = 0; i < 256; i++) {
        keccak.out[i] === claim_chain_bits[i];
    }

    // Get the appropriate state root from history
    // Since every state root in history can be found with onchain data, the prover can be *required* to give a proof for the state root. This saves
    // putting this merkle proof in the claim, which saves constraints in the keccak, and calldata during claiming.
    CheckMerkleProofStrict(history_depth)(
        leaf <== state_root,
        pathElements <== history_pathElements,
        pathIndices <== Num2Bits(history_depth)(block_number),
        root <== history_root
    );

    // Figure out whether the claim exists in the state root
    assert(address + 2 * coin_bits + history_depth < 254);
    signal claim_leaf <== address * (coin_bits^2) * history_depth + 
        first_coin * coin_bits * history_depth + 
        last_coin * history_depth + 
        block_number;

    signal state_root_calculated <== CheckMerkleProof(state_depth)(
        leaf <== claim_leaf, // TODO: make sure leaves are represented as a single field element in state transition function
        pathElements <== state_pathElements,
        pathIndices <== Num2Bits(state_depth)(state_pathIndex)
    );
    signal claim_is_valid <== IsEqual()(in <== [state_root, state_root_calculated]);

    // If the claim exists in the state root, add it to the processed claims
    signal updated_filtered_root <== UpdateLeaf(filtered_depth)(
        old_leaf <== 0,
        new_leaf <== claim_leaf,
        pathElements <== filtered_pathElements,
        pathIndices <== Num2Bits(filtered_depth)( in <== filtered_count),
        old_root <== filtered_root
    );

    signal new_filtered_count <== filtered_count + claim_is_valid;
    signal new_filtered_root <== (updated_filtered_root - filtered_root) * claim_is_valid + filtered_root;

    // Output the new values
    step_out[0] <== next_claim_chain[0];
    step_out[1] <== next_claim_chain[1];
    step_out[2] <== new_filtered_root;
    step_out[3] <== new_filtered_count;
    step_out[4] <== history_root;
}

template MultiNum2Bits(n, bits) {
    signal input in[n];
    signal output out[bits * n];

    component n2b[n];
    for (var i = 0; i < n; i++) {
        n2b[i] = Num2Bits(bits);
        n2b[i].in <== in[i];
        for (var j = 0; j < bits; j++) {
            out[i * bits + j] <== n2b[i].out[j];
        }
    }
}

// TODO: this is so ugly, we should get rid of it
template concat8(l1,l2,l3,l4,l5,l6,l7,l8) {
    signal input i1[l1];
    signal input i2[l2];
    signal input i3[l3];
    signal input i4[l4];
    signal input i5[l5];
    signal input i6[l6];
    signal input i7[l7];
    signal input i8[l8];

    signal output out[l1+l2+l3+l4+l5+l6+l7+l8];

    var prev = 0;
    for (var i = 0; i < l1; i++) {
        out[i] <== i1[i + prev];
    }

    prev += l1;
    for (var i = 0; i < l2; i++) {
        out[i] <== i2[i + prev];
    }

    prev += l2;
    for (var i = 0; i < l3; i++) {
        out[i] <== i3[i + prev];
    }

    prev += l3;
    for (var i = 0; i < l4; i++) {
        out[i] <== i4[i + prev];
    }

    prev += l4;
    for (var i = 0; i < l5; i++) {
        out[i] <== i5[i + prev];
    }

    prev += l5;
    for (var i = 0; i < l6; i++) {
        out[i] <== i6[i + prev];
    }

    prev += l6;
    for (var i = 0; i < l7; i++) {
        out[i] <== i7[i + prev];
    }

    prev += l7;
    for (var i = 0; i < l8; i++) {
        out[i] <== i8[i + prev];
    }
}

// coins_bits is 40:
// - V1 is capped to ~$100M in TVL
// - We need 1 cent increments
// - The Eth price will probably 50x at most
// 100,000,000 * 100 * 50 possible coins, which fits in 40 bits or 5 bytes.
// 
// history_depth is 20, since we can handle 4 blocks a day for a decade. We will probably mostly do 1 block per day, and v1 will probably only last a few years.
// 
// state_depth is also 40 so that it can, in principle handle a different entry per coin, this avoids an attack vector where the state is filled up
// TODO: TODO: optimise proof size. A 40 depth merkle proof requires 40 * 32 = 1280 bytes, which costs 20480 gas in calldata. We could either use a constant sized accumulator,
// or let people batch their own filtered claims using a ZKP, where the merkle proof is a private input.
//
// filtered_depth is 40 to prevent it being filled up. The only cost is prover time, as the filtered trees are only used within ZKPs
//
// field_size is 254 bits, at least for the grumpkin and bn254 cycles
// TODO: does poseidon work the same over both grumpkin and bn254, or does it depend on our scalar field?
// 
// TODO: document global parameter choice at a higher level - these are relevant to the state transition circuit too
component main { public [step_in] } = Filter(40, 14, 40, 40, 254);
