pragma circom 2.1.5;

include "./node_modules/circomlib/circuits/poseidon.circom"; // TODO: consider Poseidon2

// Distrubte takes a commitment to all claims, validates them, and outputs a commitment to the rightful owners
// 
// First we create the maybe_winners tree. Every claim is added to the maybe_winners tree,
// unless the prover provies another claim that supersedes them.
// Then we prove that the sorted_tree contains every value in the maybe_winners tree and vice_versa.
// Then we prove that the sorted_tree is sorted and disjoint, such that there are no overlapping claims.
// The sorted tree is output from the circuit.
// 
// We can be sure that every claim in the final tree is the only claim for those coins because there are no overlapping claims.
// Since it's the only claim, we can be sure it's the highest priority claim, since the only way to avoid adding a claim to the tree
// is by superseeding it.
//
// TODO: use recursion/folding rather than interation within the circuit and give the claim Merkle tree a definitive final element to avoid halt early
template Distribute(claim_levels, state_levels, upper_state_levels) {
    // Public inputs
    signal input states_root; // The state tree is a Poseidon Merkle tree which of depth upper_state_levels which contains trees of depth state_levels - upper_state_levels
    signal input claim_root; // The claim commitment is the root Poseidon Merkle tree

    // Private inputs
    signal claims[2 ** claim_levels][3]; // Each claim has [owner, start_coin, end_coin]
    signal claim_PathElements[2 ** claim_levels][claim_levels]; // Proves the claim is in the claim root
    signal ownership_PathElements[2 ** claim_levels][state_levels]; // Proves the claim is in the state root
    signal ownership_PathIndices[2 ** claim_levels][state_levels];

    signal challenge_claims[2 ** claim_levels][3];
    signal challenge_claim_PathElements[2 ** claim_levels][claim_levels]; // Proves the superseding claim is in the claim root
    signal challenge_claim_PathIndices[2 ** claim_levels][claim_levels];
    signal challenge_state_PathElements[2 ** claim_levels][state_levels]; // Proves the superseding claim is in the state 
    signal challenge_state_PathIndices[2 ** claim_levels][state_levels];

    signal output final_owners_root;

    // Add claims to the maybe_winners tree if they are valid
    // Optionally invalidate them by providing an superseding claim
    signal maybe_winners = EmptyTree(claim_levels);
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Make sure the claim is the ith in the claim tree
        {
            // Full claim includes ownership proof
            signal full_claim[3 + 2 * (state_levels)] <== concat3(3, state_levels, state_levels)(
                a <== claims[i],
                b <== ownership_PathElements[i],
                c <== ownership_PathIndices[i]
            )

            // Ensure the full claim exists in the claim tree
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
                leaf <== Poseidon(3)(inputs <== challenge_claims[i]),
                pathElements <== challenge_state_PathElements[i],
                pathIndices <== challenge_state_PathIndices[i],
            );
        }

        // TODO: check if the claim overlaps with the challenge
        // TODO: see if the challenge supersedes the claim
        // TODO: iff (claim is valid && challenge fails) insert into maybe_winners
    }


    // TODO: prove sorted tree is equivalent to maybe_winners

    // TODO: prove sorted tree is in order and disjoint

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


