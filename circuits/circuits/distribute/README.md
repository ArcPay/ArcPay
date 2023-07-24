# Post Shutdown Distribution

ZKPs are used to cheaply handle distribution of funds after shutdown.
The distribution circuits take a set of claims over coins and output the rightful final owners given those claims.

# Algorithm

Distribution involves 3 parts:
- Building the list of valid claims (where valid claims are true facts about the state history)
- Resolve any conflicts between claims
- Prove that there are no conflicting claims in the final list
- Convert the list to format that is friendly for L1 withdrawals

<!-- TODO: mention that we could also allow people to withdraw en masse to new systems using ZKPs from the final format -->
<!-- TODO: consider incentives - batchers should be compensated, and the person who posts the final 3 steps should be compensated. Batchers should be paid by the claimants idealy, and the finaliser could potentially be paid for out of the protocol's funds - perhaps the burned stake: how do we calculate the appropriate amount? Some constant? Something to do with gas costs? -->

For conceptual simplicity and good prover time, we will implement each part as a separate Nova/Groth16 circuit.

## Validation

Claims are statments like `X owns coins [a,b] in block Y`.
To lower the cost of claiming, claims are made in batches.
The state history is an ordered Merkle tree of all state trees that ever existed.

The validation algorithm achieves the following properties:
- Anyone can post a batch
- The final `validated_root` commits to the set of all valid claims
- All claims can be recovered using calldata, to execute the next steps

### Algorithm

A poseidon merkle tree of all valid claims is initialised with zeroes leaves, and its root (`validated_root`) and element count (`validated_count`) are stored onchain.
`validated_root` is initialised to the zero Merkle tree, and `validated_count` is initialised to `0`.

To claim a batch:
- The user uses their ownership proofs (i.e., merkle proofs) to generate a Nova/Groth16 ZKP which proves that their claims were true given the state history.
- The proof outputs an updated `validated_root` and `validated_count`, and a keccak hash chain of the added claims called `keccak_head`
- The contract reverts if the `initial_root` input to the proof is different to `validated_root` to minimise gas costs in case of collisions/frontrunning
- The contract verifies the proof and unrolls `keccak_head` using claims passed in as calldata
- The contract updates `validated_head` to `new_validated_head` as output by the proof

So each round of the circuit:
- Accepts public inputs: `initial_root`, `last_root`, `keccak_head`, `history_root`, `validated_count`
- Accepts private inputs: a claim, and merkle proof that the claim exists in history, a merkle proof for inserting into the claim tree
- Proves that the claim exists in history
- Inserts the claim into the `last_root` tree at index `validated_count`, giving the `new_root` tree
- Increments `validated_count`
- Updates `keccak_head` with the new claim
- Outputs the updated values, while `initial_root` is kept constant

<!-- ### Future Optimisations

There are 3 important costs we should try to minimise when making claims:
- Cost of a fully trustless claim
- Marginal cost of a batched claim
- Amortised cost of a batched claim

Our v1 algorithm minimises the marginal cost of batched claims to near the theoretical minimum (~400 gas/~$0.025). The trustless costs are very bad, requiring a groth16 proof (~300k gas/~$20 USD) for every batch including batches with just 1 claim.

In v2 we can reduce the trustless costs by replacing direct onchain verification of ZKPs with an optimistic game or recursive ZKP.
This would reduce the minimum cost per batch from ~300k gas/~$20 USD (dominated by groth16 verification) to ~5k gas/~$0.3 USD (dominated by updating a 32 byte accumulator).
The marginal cost of a batched claim is dominated by the calldata 30 bytes of calldata (20 for the address, 5 for first and last coin). In v2 we can reduce this by using indices for accounts rather than addresses, bringing the calldata to 14 bytes for ~4 billion accounts and halving the cost. -->

## Challenge Resolution

The challenge resolution circuit is also in Nova and runs iteratively. The initial input is the `validated_root` which is a poseidon Merkle tree, and each iteration takes two contradictory claims in the tree, resolves the contradiction, and updates the tree.

The first claim is called the winner and the second is the loser. The winner's block number must be greater than the loser's. The winner's leaf remains unedited. If the winner's coins are a superset of the loser's (i.e., $[0,5]$ beats $[2,3]$), the loser's leaf is deleted, and the `resolved_count` is decremented. If the loser's coins are split (i.e., $[2,3]$ beats $[0,5]$), the loser's leaf is deleted, but two new leaves are added and the `resolved_count` is incremented. If the loser's coins are truncated (i.e., $[1,5]$ beats $[1,6]$), the loser's leaf is deleted, a new leaf is added and the `resolved_count` remains the same.

Now we have a `resolved_tree` that contains all valid winning claims, but may contain additional claims.

> **How can `resolved_tree` contain additional claims?:** There's nothing in the challenge resolution circuit that *forces* all overlapping claims to be fixed, it's just an opportunity to fixed overlapping claims. The next circuit makes sure all overlapping claims have actually been dealt with.

## Proving Disjointness

The disjointness circuit takes the `resolved_tree` and a new `final_tree` as input. Its goal is to show that the `final_tree` is sorted by coin order, fully disjoint, and only contains elements from the `resolved_tree`. This proves that the final tree only contains the true winners, and, importantly, it can be deterministically calculated with onchain data, so everyone can calculate the merkle proofs they need. The `final_tree` should use keccak for gas efficiency during withdrawal.

The circuit iterates over every element in the `final_tree` and makes sure that its `end_coin` is lower than the `start_coin` of the next claim (unless it's the final claim, in which case there is no next claim). It also makes sure that the element exists in the `resolved_tree`.

Since the `start_coin[i] < end_coin[i]` for every valid claim (if the protocol operated correctly while running!!), we can check that `end_coin[i] < start_coin[i+1]` in our circuit, which proves that the claims are strictly ordered. This also means that every claim is different. We also check that `final_tree` contains at least `resolved_count` elements, by counting the number of folds.

Since we have proved that the `final_tree` contains at least `resolve_count` distinct elements that also exist in the `resolved_tree`, we know that `final` is a superset of `resolved`. To prove that the sets are strictly equal, we have to prove that all other elements are zero.

We prove that the remaining elements are zero by showing that the `resolved_count`th element is 0, and that the `resolved_count/2`th element is `h(0, 0)` etc up the tree. This doesn't necessarily fit nicely into an iteration of the disjointness circuit, but could be done in its own proof or even onchain.

### Withdrawals

TODO: convert into a keccak merkle tree of unassailable depth (i.e., coin_bits depth, since that's the maximum number of possible final claims). Note that'd probably cost 40k gas on L1, which, in addition 21k for sending Eth would massively dominate the marginal cost of claims.

## Properties

It's critical that the final result contains exactly the winning valid claims in order. The result must be fully deterministic, so that anyone can generate the tree and appropriate proofs. The proof must also be unhaltable in the sense that adversarial claims won't make it impossible to generate the proof.