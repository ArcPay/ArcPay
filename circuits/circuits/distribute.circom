pragma circom 2.1.5;

include "./node_modules/circomlib/circuits/poseidon.circom"; // TODO: consider Poseidon2

// Distrubte takes a commitment to all claims, validates them, and outputs a commitment to the rightful owners
// 
// First we create the undefeated tree. Every claim is added to the undefeated tree,
// unless the prover provides another claim that supersedes it.
// Then we prove that a new tree called the sorted tree contains every value from the undefeated tree.
// Then we prove the undefeated tree has every value from the sorted tree. This proves that
// they are permutations of each other, except if there are duplicates, which may differ between trees.
// Finally we prove that every coin range in the sorted tree is strictly greater than the last (except zero leafs which are all at the end).
// I.e., for ranges [a,b] and [c,d], that b < c.
// This proves that the only duplicates in the tree are 0 nodes
// 
// Distribute has a few properties:
// - It is deterministic wrt its inputs, so that any can calculate the output root and Merkle proofs they might need from onchain data
// - It is unjammable, in that it can take any arbitrary claim_root/states_root pair and still be executed
// - It includes all the actual winners and no other claims
//
// TODO: fix issue around adding the same claim multiple times (makes it non-deterministic, and solutions to that seem to make it jammable)
// TODO: use recursion/folding rather than interation within the circuit and give the claim Merkle tree a definitive final element to avoid halt early
template Distribute(claim_levels, state_levels, upper_state_levels) {
    // Public inputs
    signal input states_root; // The state tree is a Poseidon Merkle tree which of depth upper_state_levels which contains trees of depth state_levels - upper_state_levels
    signal input claim_root; // The claim commitment is the root Poseidon Merkle tree
    signal input undefeated_root;
    signal input sorted_root;

    // Advice for building the undefeated tree
    signal input claims[2 ** claim_levels][3]; // Each claim has [owner, start_coin, end_coin]
    signal input claim_PathElements[2 ** claim_levels][claim_levels]; // Proves the claim is in the claim root
    signal input ownership_PathElements[2 ** claim_levels][state_levels]; // Proves the claim is in the state root
    signal input ownership_PathIndices[2 ** claim_levels][state_levels];

    signal input challenge_claims[2 ** claim_levels][3];
    signal input challenge_claim_PathElements[2 ** claim_levels][claim_levels]; // Proves the superseding claim is in the claim root
    signal input challenge_claim_PathIndices[2 ** claim_levels][claim_levels];
    signal input challenge_state_PathElements[2 ** claim_levels][state_levels]; // Proves the superseding claim is in the state 
    signal input challenge_state_PathIndices[2 ** claim_levels][state_levels];

    signal input undefeated_pathElements[2 ** claim_levels][state_levels];

    // Advice for proving that the sorted and undefeated trees are equivalent
    signal input undefeated_leaves[2 ** claim_levels];
    signal input undefeated_pathElements[2 ** claim_levels][state_levels];
    signal input sorted_leaves[2 ** claim_levels];
    signal input sorted_pathElements[2 ** claim_levels][state_levels];
    signal input permutation_Indices[2 ** claim_levels];
    signal input reverse_permutation_Indices[2 ** claim_levels];

    // Add claims to the undefeated tree if they are valid
    // Optionally invalidate them by providing an superseding claim
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Make sure the claim is the ith in the claim tree
        {
            // Full claim includes ownership proof
            signal full_claim[3 + 2 * (state_levels)] <== concat3(3, state_levels, state_levels)(
                a <== claims[i],
                b <== ownership_PathElements[i],
                c <== ownership_PathIndices[i]
            )

            // Ensure the full claim is next in the claim tree
            claim_root === CheckMerkleProof(claim_levels)(
                leaf <== Poseidon(3 + state_levels)(inputs <== full_claim),
                pathElements <== claim_PathElements,
                pathIndices <== Num2Bits(claim_levels)(in <== i)
            );
        }

        // Make sure the claim is valid
        signal calculated_state_root <== CheckMerkleProof(state_levels)(
            leaf <== Poseidon(3)(inputs <== claims[i]),
            pathElements <== ownership_PathElements[i],
            pathIndices <== ownership_PathIndices[i],
        );
        signal claim_is_valid <== IsEqual()(in <== [calculated_state_root, states_root]);

        // Optionally supersede the claim
        // Make sure the challenger is a real leaf in the claim tree, and is a valid proof of ownership
        // The prover can always find *some* challenger in the tree as long as there is at least one valid claim
        signal challenge_leaf <== Poseidon(3)(inputs <== challenge_claims[i]);
        {
            // Full challenge includes ownership proof
            signal challenge[3 + 2 * (state_levels)] <== concat3(3, state_levels, state_levels)(
                a <== challenge_claims[i],
                b <== challenge_state_PathElements[i],
                c <== challenge_state_PathIndices[i]
            )

            // Ensure the full challenge exists in the claim tree
            claim_root === CheckMerkleProof(claim_levels)(
                leaf <== Poseidon(3 + state_levels)(inputs <== challenge),
                pathElements <== challenge_claim_PathElements,
                pathIndices <== challenge_claim_PathIndices
            );

            // Ensure the challenge has a valid ownership proof
            states_root === CheckMerkleProof(state_levels)(
                leaf <== challenge_leaf,
                pathElements <== challenge_state_PathElements[i],
                pathIndices <== challenge_state_PathIndices[i],
            );
        }

        signal challenge_succeeds;
        {
            signal challenge_overlaps <== CoinRangesOverlap()(
                a[0] <== claims[i][1],
                a[1] <== claims[i][2],
                a[0] <== challenge_claims[i][1],
                a[1] <== challenge_claims[i][2],
            )

            // Since the Merkle tree of the states is in order, the block number a claim
            // is in corresponds to the first `upper_state_levels` bits of the Merkle proof's indices
            signal claim_index_bits[upper_state_levels];
            signal challenge_index_bits[upper_state_levels];
            for (var i = 0; i < upper_state_levels; i++) {
                claim_index_bits[i] <== ownership_PathIndices;
                challenge_index_bits[i] <== challenge_state_PathIndices;
            }
            signal claim_index <== Bits2Num(upper_state_levels)(in <== claim_index_bits);
            signal challenge_index <== Bits2Num(upper_state_levels)(in <== challenge_index_bits);
            signal challenge_is_later <== LessThan(upper_state_levels)(in <== [claim_index, challenge_index]);

            challenge_succeeds <== challenge_overlaps * challenge_is_later;
        }


        // iff (claim is valid && challenge fails) undefeated contains the claim at this index, otherwise it contains 0
        signal should_insert <== claim_is_valid * (1 - challenge_succeeds);
        signal calculated <== CheckMerkleProof(claim_levels)(
            leaf <== challeng_leaf * should_insert,
            pathElements <== undefeated_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(in <== i)
        );
    }

    // Prove that the sorted tree contains all elements in the undefeated tree
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Prove that the advice leaf is the ith leaf in the undefeated tree
        undefeated === CheckMerkleProof(claim_levels)(
            leaf <== undefeated_leaves[i],
            pathElements <== undefeated_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(in <== i)
        );

        // Prove that the ith leaf in the undefeated tree exists in the sorted tree
        sorted === CheckMerkleProof(claim_levels)(
            leaf <== undefeated_leaves[i],
            pathElements <-- sorted_pathElements[permutation_Indices[i]],
            pathIndices <== Num2Bits(128)(in <== permutation_Indices[i]),
        )
    }

    // Prove that the undefeated tree contains all elements in the sorted tree
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Prove that the advice leaf is the ith leaf in the sorted tree
        sorted === CheckMerkleProof(claim_levels)(
            leaf <== sorted_leaves[i],
            pathElements <== sorted_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(in <== i)
        );

        // Prove that the ith leaf in the sorted tree exists in the undefeated tree
        undefeated === CheckMerkleProof(claim_levels)(
            leaf <== sorted_leaves[i],
            pathElements <-- undefeated_pathElements[reverse_permutation_Indices[i]],
            pathIndices <== Num2Bits(128)(in <== reverse_permutation_Indices),
        )
    }

    // Verify that sorted tree is sorted, and contains no repitition except 0 leaves at the end
    for (var i = 1; i < 2 ** claim_levels; i++) {
        // If we have a zeroed value, make sure it's followed by a zero, i.e., if the previous value is zero, the current value can't be non-zero
        // Note, we've already proved that sorted_leaves[i] is indeed the ith leaf in the sorted tree
        signal curr_is_nonzero <== 1 - IsZero()(in <== sorted_leaves[i]);
        signal prev_is_zero <== IsZero()(in <== sorted_leaves[i-1]); // TODO: make sure that the compiler optimised out repeated constraints, like curr[i] is equal to prev[i+1]
        1 == NAND()(
            a <== prev_is_zero
            b <== curr_is_nonzero,
        )

        // If we have a non-zero value, make sure it's followed by zero or something higher
        // We start by assigning (a, b)) to (prev_range[1], curr_range[0]) if the !prev_is_zero
        // If prev_is_zero, (a, b) = (0, 1), which trivially passes our check
        // Then we check that a < b
        // Note, there *MUST* be a check in the claiming contract that claim[0] <= claim[1] (which ensures that prev_range[0] <= prev_range[1] and curr_range[0] <= curr_range[1])
        signal a <-- prev_is_zero ? 0 : claims[reverse_permutation_Indices[i-1]][2];
        signal b <-- prev_is_zero ? 1 : claims[reverse_permutation_Indices[i]][1];
        signal calculated_leaf_a <== Poseidon(3)(claims[reverse_permutation_Indices[i-1]]);
        signal calculated_leaf_b <== Poseidon(3)(claims[reverse_permutation_Indices[i]]);
        signal prev_nonzero <== 1 - prev_is_zero;
        prev_nonzero * (calculated_leaf_a - sorted_leaves[i-1]) === 0;
        prev_nonzero * (calculated_leaf_b - sorted_leaves[i]) === 0;
    }
}



// Concatenates 3 arrays
// Note, these extra constraints should be optimised out by the compiler
template concat3(l1, l2, l3) {
    signal input a[l1];
    signal input b[l2];
    signal input b[l3];
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

// Creates the root of a Poseidon Merkle tree where every leaf is 0
function EmptyTree(levels) {
    if (levels = 0) {
        return 0;
    }
    var last_layer = EmptyTree(levels - 1);
    return last_layer; // TODO: return Poseidon(2)(last_layer, last_layer); without creating more signals
}

template CoinRangesOverlap() {
    signal input a[2];
    signal input b[2];
    signal output out;

    signal lower_a_in_b <== LessEqThan(128)(in <== [b[0], a[0]]) * LessEqThan(128)(in <== [a[0], b[1]]);
    signal upper_a_in_b <== LessEqThan(128)(in <== [b[0], a[1]]) * LessEqThan(128)(in <== [a[1], b[1]]);
    out <== OR()(a <== lower_a_in_b, b <== upper_a_in_b);
}
