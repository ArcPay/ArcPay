pragma circom 2.1.5;

include "../node_modules/circomlib/circuits/poseidon.circom"; // TODO: consider Poseidon2
include "../node_modules/circomlib/circuits/comparators.circom";

template FilteredLeafIsValid(claim_levels, state_levels, upper_state_levels, i) {
    signal input states_root;
    signal input ownership_PathElements[2 ** claim_levels][state_levels];
    signal input ownership_PathIndices[2 ** claim_levels][state_levels];

    signal input claim_root;
    signal input claims[2 ** claim_levels][3];
    signal input claim_PathElements[2 ** claim_levels][claim_levels];

    signal input filtered_root;
    signal input filtered_leaves[2 ** claim_levels];
    signal input filtered_pathElements[2 ** claim_levels][claim_levels];

    signal input ci[2 ** claim_levels];

    signal claim_is_valid <== ClaimIsValid(claim_levels, state_levels)(
        i,
        claims[i],
        ownership_PathElements[i],
        ownership_PathIndices[i],
        claim_PathElements[i],
        states_root,
        claim_root
    );

    // Make sure the challenger is a real leaf in the claim tree with a valid proof of ownership
    // The prover can always find *some* challenger in the tree as long as there is at least one valid claim
    
    // Challenger and challenge indices are necessary to make sure the ClaimIsValid and ChallengeSucceeds templates are using the same advice values
    signal challenger[3];
    for (var j = 0; j < 3; j++) {
        challenger[j] <-- claims[ci[i]][j];
    }
    signal challenge_indices[state_levels];

    // These variables are only needed because of a compiler issue where we can't use <-- directly in the anonymous component
    signal challenge_state_PathElements[state_levels];
    for (var j = 0; j < state_levels; j++) {
        challenge_indices[j] <-- ownership_PathIndices[ci[i]][j];
        challenge_state_PathElements[j] <-- ownership_PathElements[ci[i]][j];
    }
    signal challenge_claim_PathElements[claim_levels];
    for (var j = 0; j < claim_levels; j++) {
        challenge_claim_PathElements[j] <-- claim_PathElements[ci[i]][j];
    }

    signal challenge_is_valid <== ClaimIsValid(claim_levels, state_levels)(
        i <-- ci[i],
        claim <== challenger,
        ownership_PathElements <== challenge_state_PathElements,
        ownership_PathIndices <== challenge_indices,
        claim_PathElements <== challenge_claim_PathElements,
        states_root <== states_root,
        claim_root <== claim_root
    );
    challenge_is_valid === 1;

    signal challenge_succeeds <== ChallengeSucceeds(state_levels, upper_state_levels)(
        defender <== claims[i],
        challenger <== challenger,
        defender_ownership_indices <== ownership_PathIndices[i],
        challenger_ownership_indices <== challenge_indices
    );

    // iff (claim is valid && challenge fails) filtered contains the claim at this index, otherwise it contains 0
    signal should_insert <== claim_is_valid * (1 - challenge_succeeds);
    signal claim_hash <== Poseidon(3)(claims[i]);
    filtered_leaves[i] === claim_hash * should_insert;
    CheckMerkleProofStrict(claim_levels)(
        filtered_leaves[i],
        filtered_pathElements[i],
        Num2Bits(claim_levels)(in <== i),
        filtered_root
    );
}

template ClaimIsValid(claim_levels, state_levels) {
    signal input i;
    signal input claim[3];
    signal input ownership_PathElements[state_levels];
    signal input ownership_PathIndices[state_levels];
    signal input claim_PathElements[claim_levels];
    signal input states_root;
    signal input claim_root;

    signal output out;

    // Ensure that claim was made at some point during the claiming period
    CheckMerkleProofStrict(claim_levels)(
        // Full claim includes ownership proof
        leaf <== Poseidon(3 + 2 * state_levels)(
            concat3(3, state_levels, state_levels)(
                a <== claim,
                b <== ownership_PathElements,
                c <== ownership_PathIndices
            )
        ),
        pathElements <== claim_PathElements,
        pathIndices <== Num2Bits(claim_levels)(i),
        root <== claim_root
    );

    // Check if claim actually occured in state history
    signal calculated_root <== CheckMerkleProof(state_levels)(
        leaf <== Poseidon(3)(inputs <== claim),
        pathElements <== ownership_PathElements,
        pathIndices <== ownership_PathIndices
    );
    signal is_in_state <== IsEqual()([
        calculated_root,
        states_root
    ]);

    // Make sure the claim is properly formed
    // Note, this *should* already be true since all leaves in any state tree are properly formed. This check is a precaution.
    signal properly_formed <== LessEqThan(128)([claim[1], claim[2]]);

    out <== is_in_state * properly_formed;
}

template ChallengeSucceeds(state_levels, upper_state_levels) {
    signal input defender[3];
    signal input challenger[3];
    signal input defender_ownership_indices[state_levels];
    signal input challenger_ownership_indices[state_levels];
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
        claim_index_bits[i] <== defender_ownership_indices[i];
        challenge_index_bits[i] <== challenger_ownership_indices[i];
    }
    signal claim_index <== Bits2Num(upper_state_levels)(claim_index_bits);
    signal challenge_index <== Bits2Num(upper_state_levels)(challenge_index_bits);
    signal challenge_is_later <== LessThan(upper_state_levels)([claim_index, challenge_index]);

    out <== challenge_overlaps * challenge_is_later;
}