pragma circom 2.1.5;

include "./node_modules/circomlib/circuits/poseidon.circom"; // TODO: consider Poseidon2
include "./node_modules/circomlib/circuits/gates.circom";
include "./node_modules/circomlib/circuits/comparators.circom";
include "./merkle_tree.circom";

// Distrubte takes a commitment to all claims, validates them, and outputs a commitment to the rightful owners
// 
//      1/ We create the undefeated tree. Every claim is added to the undefeated tree,
//          unless the prover provides another claim that supersedes it.
//      2/ Then we prove that a new tree called the sorted tree contains every value from the undefeated tree.
//          Then we prove the undefeated tree has every value from the sorted tree. This proves that
//          they are permutations of each other, except if there are duplicates, which may differ between trees.
//      3/ We prove that every coin range in the sorted tree is strictly greater than the last (except zero leafs which are all at the end).
//          I.e., for ranges [a,b] and [c,d], that b < c.
//          This proves that the only duplicates in the tree are 0 nodes
// 
// Distribute has a few properties:
// - It is deterministic wrt its inputs, so that any can calculate the output root and Merkle proofs they might need from onchain data
// - It is unjammable, in that it can take any arbitrary claim_root/states_root pair and still be executed
// - It includes all the actual winners and no other claims
//
// TODO: use recursion/folding rather than interation within the circuit and give the claim Merkle tree a definitive final element to avoid halt early
template Distribute(claim_levels, state_levels, upper_state_levels) {
    assert(state_levels > upper_state_levels);
    // The root of the history of all states and the proofs that each claim exists in that tree
    signal input states_root; // The state tree is a Poseidon Merkle tree which of depth upper_state_levels which contains trees of depth state_levels - upper_state_levels
    signal input ownership_PathElements[2 ** claim_levels][state_levels]; // Proves the ith claim is in the state root
    signal input ownership_PathIndices[2 ** claim_levels][state_levels];

    // The root and all leaves of the claim tree
    signal input claim_root; // The claim commitment is the root Poseidon Merkle tree
    signal input claims[2 ** claim_levels][3]; // Each claim has [owner, start_coin, end_coin]
    signal input claim_PathElements[2 ** claim_levels][claim_levels]; // Proves the claim is in the claim root

    // The root and all leaves of the undefeated tree
    signal input undefeated_root;
    signal input undefeated_leaves[2 ** claim_levels];
    signal input undefeated_pathElements[2 ** claim_levels][state_levels];

    // The root and all leaves of the final sorted tree
    signal input sorted_root;
    signal input sorted_leaves[2 ** claim_levels];
    signal input sorted_pathElements[2 ** claim_levels][state_levels];
    
    // Non deterministic challenges used as advice to prove certain claims are invalid
    // Represented as an index into the claim tree ("ci" = "challenge index")
    signal input ci[2 ** claim_levels];

    // Non deterministic advice for proving that the sorted and undefeated trees are equivalent
    signal input permutation_Indices[2 ** claim_levels];
    signal input reverse_permutation_Indices[2 ** claim_levels];

    // Ensure that the undefeated tree's elements are identical to the claim tree,
    // except where they're zeroed out when a winning challenge is provided
    for (var i = 0; i < 2 ** claim_levels; i++) {
        UndefeatedLeafRootIsValid(claim_levels, state_levels, upper_state_levels, i)(
            states_root,
            ownership_PathElements,
            ownership_PathIndices,
            claim_root,
            claims,
            claim_PathElements,
            undefeated_root,
            undefeated_leaves,
            undefeated_pathElements,
            ci
        );
    }

    // Prove that the sorted tree contains all elements in the undefeated tree
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Prove that the advice leaf is the ith leaf in the undefeated tree
        CheckMerkleProofStrict(claim_levels)(
            leaf <== undefeated_leaves[i],
            pathElements <== undefeated_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(i),
            root <== undefeated_root
        );

        // Prove that the ith leaf in the undefeated tree exists in the sorted tree
        CheckMerkleProofStrict(claim_levels)(
            leaf <== undefeated_leaves[i],
            pathElements <-- sorted_pathElements[permutation_Indices[i]],
            pathIndices <== Num2Bits(claim_levels)(permutation_Indices[i]),
            root <== sorted_root
        );
    }

    // Prove that the undefeated tree contains all elements in the sorted tree
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Prove that the advice leaf is the ith leaf in the sorted tree
        CheckMerkleProofStrict(claim_levels)(
            leaf <== sorted_leaves[i],
            pathElements <== sorted_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(i),
            root <== sorted_root
        );

        // Prove that the ith leaf in the sorted tree exists in the undefeated tree
        CheckMerkleProofStrict(claim_levels)(
            leaf <== sorted_leaves[i],
            pathElements <-- undefeated_pathElements[reverse_permutation_Indices[i]],
            pathIndices <== Num2Bits(claim_levels)(reverse_permutation_Indices[i]),
            root <== undefeated_root
        );
    }

    // Verify that sorted tree is sorted, and contains no repitition except 0 leaves at the end
    for (var i = 1; i < 2 ** claim_levels; i++) {
        ClaimsInOrder()(
            leaves <== [sorted_leaves[i-1], sorted_leaves[i]],
            claims <-- [claims[reverse_permutation_Indices[i-1]], claims[reverse_permutation_Indices[i]]]
        );
    }
}

template UndefeatedLeafRootIsValid(claim_levels, state_levels, upper_state_levels, i) {
    signal input states_root;
    signal input ownership_PathElements[2 ** claim_levels][state_levels];
    signal input ownership_PathIndices[2 ** claim_levels][state_levels];

    signal input claim_root;
    signal input claims[2 ** claim_levels][3];
    signal input claim_PathElements[2 ** claim_levels][claim_levels];

    signal input undefeated_root;
    signal input undefeated_leaves[2 ** claim_levels];
    signal input undefeated_pathElements[2 ** claim_levels][state_levels];

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
    signal challenges[3] <-- claims[ci[i]];
    signal challenge_indices[state_levels] <-- ownership_PathIndices[ci[i]];

    signal challenge_is_valid <== ClaimIsValid(claim_levels, state_levels)(
        i <-- ci[i],
        claim <== challenges,
        ownership_PathElements <-- ownership_PathElements[ci[i]],
        ownership_PathIndices <== challenge_indices,
        claim_PathElements <-- claim_PathElements[ci[i]],
        states_root <== states_root,
        claim_root <== claim_root
    );
    challenge_is_valid === 1;

    signal challenge_succeeds <== ChallengeSucceeds(state_levels, upper_state_levels)(
        defender <== claims[i],
        challenger <== challenges,
        defender_ownership_indices <== ownership_PathIndices[i],
        challenger_ownership_indices <== challenge_indices
    );

    // iff (claim is valid && challenge fails) undefeated contains the claim at this index, otherwise it contains 0
    signal should_insert <== claim_is_valid * (1 - challenge_succeeds);
    signal claim_hash <== Poseidon(3)(claims[i]);
    undefeated_leaves[i] === claim_hash * should_insert;
    CheckMerkleProofStrict(claim_levels)(
        undefeated_leaves[i],
        undefeated_pathElements[i],
        Num2Bits(claim_levels)(in <== i),
        undefeated_root
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
    out <== IsEqual()([
        calculated_root,
        states_root
    ]);
}

// Concatenates 3 arrays
// Note, these extra constraints should be optimised out by the compiler
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

template ChallengeSucceeds(state_levels, upper_state_levels) {
    signal input defender[2];
    signal input challenger[2];
    signal input defender_ownership_indices[state_levels];
    signal input challenger_ownership_indices[state_levels];
    signal output out;

    signal challenge_overlaps <== CoinRangesOverlap()(
        defender,
        challenger
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

template ClaimsInOrder() {
    signal input leaves[2];
    signal input claims[2][3];

    // If we have a zeroed value, make sure it's followed by a zero, i.e., if the previous value is zero, the current value can't be non-zero
    signal curr_is_zero <== IsZero()(leaves[1]);
    signal curr_is_nonzero <== 1 - curr_is_zero;
    signal prev_is_zero <== IsZero()(leaves[0]);
    signal following_valid <== NAND()(
        a <== prev_is_zero,
        b <== curr_is_nonzero
    );
    following_valid === 1;

    // If we have a non-zero value, make sure it's followed by zero or something higher
    // We start by assigning (a, b)) to (prev_range[1], curr_range[0]) if the !prev_is_zero
    // If prev_is_zero, (a, b) = (0, 1), which trivially passes our check
    // Then we check that a < b
    // Note, there *MUST* be a check in the claiming contract that claim[0] <= claim[1] (which ensures that prev_range[0] <= prev_range[1] and curr_range[0] <= curr_range[1])
    signal a <-- prev_is_zero ? 0 : claims[0][2];
    signal b <-- prev_is_zero ? 1 : claims[1][1];
    signal calculated_leaf_a <== Poseidon(3)(claims[0]);
    signal calculated_leaf_b <== Poseidon(3)(claims[1]);
    signal prev_nonzero <== 1 - prev_is_zero;
    prev_nonzero * (calculated_leaf_a - leaves[0]) === 0;
    prev_nonzero * (calculated_leaf_b - leaves[1]) === 0;
}

component main {public [states_root, claim_root, sorted_root]} = Distribute(20, 30, 10); // TODO: select minimum reasonable parameters