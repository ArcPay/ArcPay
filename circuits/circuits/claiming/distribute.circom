pragma circom 2.1.5;

include "../node_modules/circomlib/circuits/poseidon.circom"; // TODO: consider Poseidon2
include "../node_modules/circomlib/circuits/gates.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "../merkle_tree.circom";
include "./utils.circom";
include "./challenge.circom";

// Distrubte takes a commitment to all claims, validates them, and outputs a commitment to the rightful owners
// 
//      1/  First, we create the "filtered" tree. Every valid claim is added to the filtered tree,
//          unless the prover provides a challenge claim that supersedes it.
//      2/  Then we prove that the "sorted" tree contains every value from the filtered tree and vice versa.
//          This proves that they are permutations of each other, except if there are duplicates, which may differ between trees.
//      3/  Then we prove that every coin range in the sorted tree is strictly greater than the last
//          I.e., for ranges [a,b] and [c,d], that b < c.
//          This proves that there are no duplicates
//
// We know that all claims in the sorted tree are disjoint because of step 3, and we know that every valid unchallengable claim is in the sorted tree, because
// they can only be removed by being invalid or challenged. So we know that the sorted tree consists of the actual exactly the rightful owners (according to the claims).
// 
// Distribute must also be deterministic wrt its inputs, so that any can calculate the output root and Merkle proofs they might need from onchain data.
// It must also be unjammable, in that it can take any arbitrary claim_root/states_root pair and still be executed.
//
// TODO: use Nova recursion/folding rather than interation within the circuit and give the claim Merkle tree a definitive final element to avoid halt early
template Distribute(claim_levels, state_levels, upper_state_levels) {
    // The root of the history of all states and the proofs that each claim exists in that tree
    signal input states_root; // The state tree is a Poseidon Merkle tree which of depth upper_state_levels which contains trees of depth state_levels - upper_state_levels
    signal input ownership_PathElements[2 ** claim_levels][state_levels]; // Proves the ith claim is in the state root
    signal input ownership_PathIndices[2 ** claim_levels][state_levels];
    assert(state_levels > upper_state_levels);

    // The root and all leaves of the claim tree
    signal input claim_root; // The claim commitment is the root Poseidon Merkle tree
    signal input claims[2 ** claim_levels][3]; // Each claim has [owner, start_coin, end_coin] TODO: add nonce (if added to main circuits)
    signal input claim_PathElements[2 ** claim_levels][claim_levels]; // Proves the claim is in the claim root

    // The root and all leaves of the filtered tree
    signal input filtered_root;
    signal input filtered_leaves[2 ** claim_levels];
    signal input filtered_pathElements[2 ** claim_levels][claim_levels];

    // The root and all leaves of the final sorted tree
    signal input sorted_root;
    signal input sorted_leaves[2 ** claim_levels];
    signal input sorted_pathElements[2 ** claim_levels][claim_levels];
    
    // Non deterministic challenges used as advice to prove certain claims are invalid
    // Represented as an index into the claim tree ("ci" = "challenge index")
    signal input ci[2 ** claim_levels];

    // Non deterministic advice for proving that the filtered and sorted trees are equivalent
    signal input permutation_Indices[2 ** claim_levels];
    signal input reverse_permutation_Indices[2 ** claim_levels];

    // ---- Step 1 ----
    // Ensure that the filtered tree's elements are identical to the claim tree,
    // except where they're zeroed out when a winning challenge is provided
    for (var i = 0; i < 2 ** claim_levels; i++) {
        FilteredLeafIsValid(claim_levels, state_levels, upper_state_levels, i)(
            states_root,
            ownership_PathElements,
            ownership_PathIndices,
            claim_root,
            claims,
            claim_PathElements,
            filtered_root,
            filtered_leaves,
            filtered_pathElements,
            ci
        );
    }

    // ---- Step 2 ----
    // Prove that the sorted tree contains all elements in the filtered tree
    signal hack_1[2**claim_levels][claim_levels]; // "hack" signal is workaround for https://github.com/iden3/circom/issues/189
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Prove that the advice leaf is the ith leaf in the filtered tree
        CheckMerkleProofStrict(claim_levels)(
            leaf <== filtered_leaves[i],
            pathElements <== filtered_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(i),
            root <== filtered_root
        );

        // Prove that the ith leaf in the filtered tree exists in the sorted tree
        for (var j = 0; j < claim_levels; j++) {
            hack_1[i][j] <-- sorted_pathElements[permutation_Indices[i]][j];
        }
        CheckMerkleProofStrict(claim_levels)(
            leaf <== filtered_leaves[i],
            pathElements <-- hack_1[i],
            pathIndices <== Num2Bits(claim_levels)(permutation_Indices[i]),
            root <== sorted_root
        );
    }

    // Prove that the filtered tree contains all elements in the sorted tree
    signal hack_2[2**claim_levels][claim_levels]; // "hack" signal is workaround for https://github.com/iden3/circom/issues/189
    for (var i = 0; i < 2 ** claim_levels; i++) {
        // Prove that the advice leaf is the ith leaf in the sorted tree
        CheckMerkleProofStrict(claim_levels)(
            leaf <== sorted_leaves[i],
            pathElements <== sorted_pathElements[i],
            pathIndices <== Num2Bits(claim_levels)(i),
            root <== sorted_root
        );

        // Prove that the ith leaf in the sorted tree exists in the filtered tree
        for (var j = 0; j < claim_levels; j++) {
            hack_2[i][j] <-- filtered_pathElements[reverse_permutation_Indices[i]][j];
        }
        CheckMerkleProofStrict(claim_levels)(
            leaf <== sorted_leaves[i],
            pathElements <-- hack_2[i],
            pathIndices <== Num2Bits(claim_levels)(reverse_permutation_Indices[i]),
            root <== filtered_root
        );
    }

    // ---- Step 3 ----
    // Verify that sorted tree is sorted, and contains no repitition except 0 leaves at the end
    // "hack" signal is workaround for https://github.com/iden3/circom/issues/189
    signal sorted_claims_hack[2 ** claim_levels][3];
    for (var i = 0; i < 2 ** claim_levels; i++) {
        for (var j = 0; j < 3; j++) {
            sorted_claims_hack[i][j] <-- claims[reverse_permutation_Indices[i]][j];
        }
    }

    for (var i = 1; i < 2 ** claim_levels; i++) {
        ClaimsInOrder()(
            leaves <== [sorted_leaves[i-1], sorted_leaves[i]],
            claims <-- [sorted_claims_hack[i-1], sorted_claims_hack[i]]
            // TODO: pass claims in like this
            // claims <-- [claims[reverse_permutation_Indices[i-1]], claims[reverse_permutation_Indices[i]]]
        );
    }
}

// ClaimsInOrder verifies that a list of leaves strictly ascends as follows, where H is a hash function:
// H([0-10]), H([12-15]) ... H([1001-1005]), 0, 0, ..., 0
//
// This requires two checks:
// - Only zeroes can follow zeroes
// - Non-zero values must be ordered
template ClaimsInOrder() {
    signal input leaves[2];
    // claims is unconstrained advice, since we conditionally check that the claim hashes to the leaf in the component
    // It needs to be passed the correct preimages for non-zero nodes or witness generation will fail
    signal input claims[2][3]; 

    signal curr_is_zero <== IsZero()(leaves[1]);
    signal curr_is_nonzero <== 1 - curr_is_zero;
    signal prev_is_zero <== IsZero()(leaves[0]);

    // If we have a zeroed value, make sure it's followed by a zero
    // i.e., if the previous value is zero, the current value can't be non-zero: NAND(prev_is_zero, curr_is_nonzero)
    signal following_valid <== NAND()(
        a <== prev_is_zero,
        b <== curr_is_nonzero
    );
    following_valid === 1;

    // Ensure claims are in order
    // Note, since this component is used on the filtered tree, each claim should already have been validated, so claims[i][1] <= claims[i][2]
    // Set passing_claims to values that pass the ordering check
    signal passing_claims[2][3];
    if (curr_is_nonzero) {
        for (var i = 0; i < 2; i++) {
            for (var j = 0; j < 3; j++) {
                passing_claims[i][j] <-- claims[i][j];
            }
        }
    } else {
        passing_claims[0][0] <-- 0;
        passing_claims[0][1] <-- 0;
        passing_claims[0][2] <-- 0; // Upper end of lower range
        passing_claims[1][0] <-- 0;
        passing_claims[1][1] <-- 1; // Lower end of upper range
        passing_claims[1][2] <-- 0;
    }
    signal calculated_lt <== LessThan(128)(
        passing_claims[0][2],
        passing_claims[1][1]
    );
    calculated_lt === 1;
    
    // Ensure that the claims hash to the provided leaves for all non-zero leaves
    signal calculated_leaf_a <== Poseidon(3)(claims[0]);
    signal calculated_leaf_b <== Poseidon(3)(claims[1]);
    curr_is_nonzero * (calculated_leaf_a - leaves[0]) === 0;
    curr_is_nonzero * (calculated_leaf_b - leaves[1]) === 0;
}

component main {public [states_root, claim_root, sorted_root]} = Distribute(2, 5, 3); // TODO: select minimum reasonable parameters