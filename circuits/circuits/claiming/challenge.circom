pragma circom 2.1.5;

include "../node_modules/circomlib/circuits/poseidon.circom"; // TODO: consider Poseidon2
include "../node_modules/circomlib/circuits/comparators.circom";

// Every leaf in the filtered tree is either equal to the same node in the claim tree, or it is zero
// The leaf is 0 if it is invalid or it is beaten by a challenger
template FilteredLeafIsValid(claim_levels, state_levels, upper_state_levels, i) {
    // Merkle roots
    signal input states_history_root;
    signal input claim_root;
    signal input filtered_root;

    // Defender
    signal input defender[3];
    signal input defender_state_PathElements[state_levels];
    signal input defender_state_PathIndices[state_levels];
    signal input defender_claim_PathElements[claim_levels];

    // Challenger
    signal input challenger_index;
    signal input challenger[3];
    signal input challenger_state_PathElements[state_levels];
    signal input challenger_state_PathIndices[state_levels];
    signal input challenger_claim_PathElements[claim_levels];

    // Results
    signal input filtered_pathElements[claim_levels];

    signal claim_is_valid <== IsValidClaim(claim_levels, state_levels)(
        i,
        defender,
        defender_state_PathElements,
        defender_state_PathIndices,
        defender_claim_PathElements,
        states_history_root,
        claim_root
    );

    // Make sure the challenger is a real leaf in the claim tree with a valid proof of ownership
    // The prover can always find *some* challenger in the tree as long as there is at least one valid claim
    signal is_valid_challenge <== IsValidClaim(claim_levels, state_levels)(
        challenger_index,
        challenger,
        challenger_state_PathElements,
        challenger_state_PathIndices,
        challenger_claim_PathElements,
        states_history_root,
        claim_root
    );
    is_valid_challenge === 1;

    signal is_successful_challenge <== IsSuccessfulChallenge(state_levels, upper_state_levels)(
        defender <== defender,
        challenger <== challenger,
        defender_state_indices <== defender_state_PathIndices,
        challenger_state_indices <== challenger_state_PathIndices
    );

    // if the claim is valid and the challenge doesn't succeed, the leaves in the claim and filtered trees should be equal
    signal should_be_equal <== claim_is_valid * (1 - is_successful_challenge);
    signal claim_hash <== Poseidon(3)(defender);
    signal filtered_leaf <== claim_hash * should_be_equal;
    CheckMerkleProofStrict(claim_levels)(
        filtered_leaf,
        filtered_pathElements,
        Num2Bits(claim_levels)(in <== i),
        filtered_root
    );
}

// Asserts that the claim is in the claim tree
// Returns whether the claim is properly formed and is in the state history
template IsValidClaim(claim_levels, state_levels) {
    signal input i;
    signal input claim[3];
    signal input state_PathElements[state_levels];
    signal input state_PathIndices[state_levels];
    signal input claim_PathElements[claim_levels];
    signal input states_history_root;
    signal input claim_root;

    signal output out;

    // Ensure that claim was made at some point during the claiming period
    CheckMerkleProofStrict(claim_levels)(
        // Full claim includes ownership proof
        leaf <== Poseidon(3 + 2 * state_levels)(
            concat3(3, state_levels, state_levels)(
                a <== claim,
                b <== state_PathElements,
                c <== state_PathIndices
            )
        ),
        pathElements <== claim_PathElements,
        pathIndices <== Num2Bits(claim_levels)(i),
        root <== claim_root
    );

    // Check if claim actually occured in state history
    signal calculated_root <== CheckMerkleProof(state_levels)(
        leaf <== Poseidon(3)(inputs <== claim),
        pathElements <== state_PathElements,
        pathIndices <== state_PathIndices
    );
    signal is_in_state <== IsEqual()([
        calculated_root,
        states_history_root
    ]);

    // Make sure the claim is properly formed
    // Note, this *should* already be true since all leaves in any state tree are properly formed. This check is a precaution.
    // CAUTION: If a leaf in the state tree is improperly formed, then asserting out === 1 will jam the proof!!!
    signal properly_formed <== LessEqThan(128)([claim[1], claim[2]]);

    out <== is_in_state * properly_formed;
}

template IsSuccessfulChallenge(state_levels, upper_state_levels) {
    signal input defender[3];
    signal input challenger[3];
    signal input defender_state_indices[state_levels];
    signal input challenger_state_indices[state_levels];
    signal output out;

    signal challenge_overlaps <== CoinRangesOverlap()(
        a <== [defender[1], defender[2]], // defender[0] and challenger[0] are addresses
        b <== [challenger[1], challenger[2]]
    );

    // Since the Merkle tree of the states is in order, the block number a claim
    // is in corresponds to the first `upper_state_levels` bits of the Merkle proof's indices
    signal claim_index_bits[upper_state_levels];
    signal challenge_index_bits[upper_state_levels];
    for (var i = 0; i < upper_state_levels; i++) {
        claim_index_bits[i] <== defender_state_indices[i];
        challenge_index_bits[i] <== challenger_state_indices[i];
    }
    signal claim_index <== Bits2Num(upper_state_levels)(claim_index_bits);
    signal challenge_index <== Bits2Num(upper_state_levels)(challenge_index_bits);
    signal challenge_is_later <== LessThan(upper_state_levels)([claim_index, challenge_index]);

    out <== challenge_overlaps * challenge_is_later;
}
