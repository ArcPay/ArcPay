# Payment Rollups

Payments are a huge market that, if conquered, could make Eth a true money. Visa alone settles over [\$1T per month](https://bit.ly/3p5Q7pL). By using cryptoeconomics instead of underwriting transactions, we can undercut existing payment providers, while offering far stronger security to users.

Recently, L2s have been built on top of blockchains to minimse fees while inheriting security from the underlying blockchain. Strong L2s, like rollups with onchain calldata are limited by Ethereum's data throughput. Only state channel networks and rollups with DA (data availability) proofs currently allow arbitrary data scaling, which is necessary for low fees, but both make substantial security tradeoffs. We present a new type of L2 called a Payment Rollup, which combines their benefits.

|                | State Channels    | DA Rollup    | Payment Rollup  |
| -----------    | -----------       | -----------  | -----------     |
| Escape Hatch   | ✅ Individual      | ❌ m-of-n    | ✅ Individual   |
| Finality       | ✅ Instant         | ❌ L1        | 🦺 Instant*     |
| Capital Lockup | ❌ O(throughput)   | ✅ O(1)      | ✅ O(1)         |
| Payment Limit  | ❌ Channel Balance | ✅ None      | ✅ None         |
| Theft Checkup  | ❌ ~Daily.         | ✅ Never     | 🦺 ~Monthly     |

<sup>*assuming the rollup keeps running</sup>

## Abstract

A payment rollup is a ZK rollup with a centralised staked sequencer and an escape hatch that only uses self custodial data, rather than relying on L1 calldata or a DA committee to rebuild the state. It uses a UTXO model where every token is labelled and doesn't (currently) support private transactions.

[Instant payments](#Instant-Payments) are achieved with promises from the sequencer. Censorship resistance is achieved with a `force_include` function. If it doesn't update the state or make good on a promise the sequencer is slashed and the rollup goes into shutdown.

[Data scaling](#Data-Scaling) is achieved with an optimistic escape hatch. During shutdown, users have a month to prove ownership of their tokens. Newer proofs invalidate older proofs for the same tokens. To get full self custody of their tokens, users can force the sequencer to provide proof of ownership with a similar mechanism to `force_include`.

Instant finality depends on the sequencer not being slashed. True finality happens when the user has an ownership proof for a state root that has reached L1 finality.

During normal operation, users can reshuffle their tokens to maintain a single ownership proof for all their funds. Tokens are points in an high dimensional space so that shuffling can work around inactive users. A special shuffle tx type keeps the old proofs valid until all shuffled users sign their new proofs.

# Details

## Instant Payments

### Forced Inclusion

Having a centralised sequencer is crucial for instant transactions. To make promises about future payments, the sequencer needs to know the future state in advance without worrying about users altering it. However, users need to be able to send transactions permisionlessly to circumvent censorship by the sequencer.

Often rollups achieve censorship resistance by decentralising the sequencer, but since we need a centralised sequencer we need to rely on `force_include`. Forced transactions are "locked in" onchain for a few blocks before they're included so the sequencer can read them before making promises about the future state. The sequencer must prove they included all forced transactions to update the state.

<figure>
  <img src="https://i.imgur.com/wT2pNnS.jpg" alt="Diagram that resembles livestock pen illustrating how transactions are held in containers until they're included.">
  <figcaption><em>Initially, the sequencer can make promises about blocks <code>n</code> and <code>n+1</code>. After proving the state transition for block <code>n</code>, they can make promises about blocks <code>n+1</code> and <code>n+2</code>.</em></figcaption>
</figure>

If the sequencer refuses to update the state they are slashed for their entire stake. When the sequencer is slashed we disable deposits and L2->L2 payments, freeze the state, and let people withdraw their funds with the exit game [described below](#Data-Scaling). This achieves trustlessness and self-sovereignty in the sense that we can always force any transaction we like while the sequencer is operating, and when the sequencer fails, we can always return our funds to the ~trustless L1.

### Offchain Payments

We use the onchain queue if the sequencer is censoring us, but in the cooperative case we simply send the transaction to the sequencer offchain, who includes it in the next state, skipping the queue.

Due to locking in `force_include`, the sequencer can calculate the state up to `k` blocks in the future. Therefore, the sequencer can promise to execute unforced transactions without fear that the user will invalidate them by forcing a double spend. That means the sequencer can safely risk their entire stake on a promise like "Bob will have tokens 1-100 in block 10."

Suppose Alice is buying an orange from Bob. She sends her transaction directly to the sequencer, who signs it, promising that the tokens will go to Bob in block `X`. This is called the receipt. Alice gives the receipt to Bob, who takes it as a strong guarantee of payment, and gives the orange to Alice.

![](https://i.imgur.com/EtxFtM9.jpg)




Bob holds on to the receipt until block `X`, when he asks the sequencer to prove that his tokens are included. If the sequencer doesn't respond, he takes the receipt onchain, and if the prover can't prove that he tokens are included, the sequencer is slashed and Bob earns a reward. To prove that the promise was fulfilled, the sequencer provides an [escape pod ticket](#Escape-Pods), which Bob holds in case the rollup shuts down.

![](https://i.imgur.com/JV9DBUA.jpg)

### Lazy Sequencer

The sequencer is given a cut of each offchain payment to incentivise them to confirm offchain transactions. However, if Alice simply signs a TX giving Bob 99% and the sequencer 1%, then the sequencer is instantly certain that they will recieve their cut, and have no incentive to return the signed receipt. Remember, the signed receipt is essential to prove to Bob that the transaction will be complete.

Instead, we implement a simple game between Alice and sequencer. Alice sends a TX giving 98% to Bob, and burning 2%. This TX has the special property that it can be converted to a new TX giving 98% to Bob, 1% to the sequencer and 1% back to Alice, as long as the sequencer and Alice mutually agree. So, in order to earn their fee, the sequencer signs the receipt and sends it to Alice. Then Alice signs it to get her cut back, and sends it back to the sequencer. Now Alice has a receipt that she can send to Bob proving that the transaction will go through.

[TODO]: <> (diagram of messages between Alice, Bob, and the Sequencer)

Note, Alice could spite the sequencer and force them to include the transaction while not being paid their fee, but that would cost her 1% of the original transcation, and it's unlikely that many users would do that. This is more problematic for a rollup with onchain calldata, as the Sequencer pays a non-negligible gas cost to include a transaction, and could be forced to make a loss.

This game can be enforced within the rollup's state transition function (i.e., in the circuit for a ZK rollup). We do this by having only 3 valid kinds of transactions:
 - Any transaction from the queue
 - Queue skipping transactions that burn 2%
 - Queue skipping transactions that would have burned 2%, but mutually decided to split the 2% between the sender and sequencer

## Data Scaling

The conventional method to scale data for rollups is with DA sampling. This introduces a an additional m-of-n security assumption to withdraw funds. This may be the best solution for a Turing complete, VM-based rollup, because you may need the whole state to prove ownership of your funds. However, for the payments rollup described below, a user can simply use their receipts to prove ownership, while only relying on L1.

### UTXO Payment Rollups

[The UTXO model](TODO), popularised by Bitcoin, is a model for digital currencies. Valid tokens are called UTXOs (unspent transaction outputs), are they can either be minted (i.e., by mining), or created by spending previous UTXOs.

[::]: <> (TODO: show a diagram of the UTXO model)

We can succinctly represent the state of a UTXO payment rollup as two Merkle trees. The first tree contains transactions, the second contains spent transactions. To make a payment, you must prove that you have a transaction in the transaction tree that *isn't* in the spent transaction tree, then the two trees are updated accordingly.

[::]: <> (TODO: diagram of the two tree model)

This is a reasonable model for our scaled rollup. To update the state, the sequencer posts the states of both trees (probably hashed together to save gas), and a ZK proof showing that it applied valid transactions to create some new state.

However, these Merkle trees are insufficient as an escape hatch. In order to make a withdrawl, the user would have to prove membership in the transaction tree, and non-membership in the spent transaction tree. The problem is that the roots change as transactions are processed, and earlier Merkle proofs are invalidated. This is a particularly big problem for non-membership in the spent transaction tree.

There is a generalisation of Merkle trees called [accumulators](TODO). [Some accumulators](https://eprint.iacr.org/2020/777.pdf) allow us to all update our proofs with the same data, but due to a [well known impossibility result](TODO) the amount of data required for this is linear in the number of changes. To achieve arbitrary scaling with this method we'd have to make that data available, probably through a data availability committee, which defeats the purpose of this construction.

### Escape Pods

To add an escape hatch to the two tree model, we use escape pods. Escape pods are simply the Merkle root of all the valid transactions in the current block. When Bob's transaction is included in a block, he asks the server for a proof that his transaction is in the escape pod, we call this a ticket of the escape pod. When the rollup shuts down, he uses his ticket to claim his funds, which are given to him once everyone has the chance to make their claims.

If the server doesn't give Bob his ticket, he can go into an onchain queue to request it by using his receipt. If the sequencer doesn't provide a correct ticket in time, they are slashed. Additional complex game theoretic mechanisms could be added where the sequencer earns a fee for each ticket, but the simple queue mechanism is probably sufficient: the Sequencer should simply address the ticket request offchain, to alleviate the threat of having to pay gas costs to dequeue it.

### LoW (Lots of Wei)

What if I get an escape pod ticket, then I spend my tokens? This means I'm able to claim spent tokens! What if I spend tokens to an address I own and get tickets for both? Then I'd be able to double-spend by withdrawing both the same token with both tickets.

The simple solution, is to number every individual token. Every ticket will specify which particular tokens it claims, and the escape pods will be numbered in time. Tickets for later escape pods will supersede earlier ones, and if I am the latest owner of a token, I know that no one can produce a ticket for a later escape pod than me.

This can be thought of as an alternative to the UTXO model. The balances of all users is represented as an ordered list of tokens and the users who own them. When money is deposited in the rollup, new tokens are minted at the end of the list. When tokens are withdrawn from the rollup, they are added to a Merkle tree of unusable tokens. It's important that the unusable tokens are specified onchain during normal withdrawls, as the list of withdrawn tokens is crucial to prevent double spending during shutdown.

[::]: <> (diagram showing "user x owns tokens 0-154, user y owns tokens 155-800, ..., tokens 1590-1778 are unspendable, ..., total tokens 2999234882")

The LoW model is not as naturally ammenable to efficient data structures like Merkle trees as the UTXO model. But note, we are not particularly compute constrained, as the computation of new updates only needs to be done on a single machine. We do have some limitations because the computation needs to be done as a ZKP, but this is a tractable engineering problem.

One basic idea of how to implement LoW is as a [sparse Merkle tree](TODO). Each entry in the tree is `[start_token, end_token, address]`, and if our rollup can handle `2^256` [wei](TODO) in its lifetime, and Ethereum addresses are 160 bits long, the merkle proofs for normal operation are `256 + 256 + 160 = 672` elements long. This is fine since none of these proofs are ever directly onchain, and with [folding](TODO) or [recursion](TODO) and [SNARK friendly hash functions](TODO) this could be quite efficient. The major cost is probably in verifying traditional ECDSA signatures in the SNARK to prove ownership of coins. For this, we can hopefully use [spartan-ecdsa](TODO).

### Shutdown

Shutdown occurs when the sequencer fails to perform its duties and is slashed. The shutdown period has two phases: claiming, and resolution. The claiming phase lasts long enough for everyone to reasonably claim their funds. Somewhere between 2 weeks and 2 months seems reasonable. During that time, the only action available on the rollup is to add claims to an onchain queue. These claims include the transaction ID, Merkle proof, and escape pod number. An optimised version would use an accumulator with short constant sized proofs for the membership proofs like [KZG](TODO). TODO: is KZG really a constant sized proof, also, since it needs a trusted setup of fixed size, is it acceptable for potentially arbitrary sized escape pods?

During resolution, we determine who owns which tokens and send them to the appropriate people. This can be done in a smart contract, but should probably be done optimistically or in a SNARK. In a SNARK, for example, we would write a circuit that accepts the list of withdrawn funds, the list of escape pods, and the list of claims. The SNARK would output who is owed how much. The contract would verify the SNARK, make sure the inputs to the SNARK match the actual onchain values, then send the funds.

The proving should be decentralised. The simplest way to do this is allow anyone to produce a proof, and give them a small reward. This results in a race scenario, which may waste overall effort, but is simple. To make sure the proof is eventually provided, the reward could gradually increase with the blocknumber.

### Security Assumptions

Let's return to Alice and Bob. What exactly do they know about their funds during their transaction?

#### Finality

Alice signs a transaction and sends it to the sequencer.
The sequencer returns a receipt signing her transaction.
Alice gives the transaction to Bob.
*Bob knows that his payment will be included in the next block, assuming the sequencer stays online, and doesn't want to be slashed with the receipt*
Bob waits until the next block of L2 transactions.
Bob asks the sequencer for a proof that his transaction is included in the most recent escape pod.
The sequencer returns the proof.
*Bob knows that he can trustlessly withdraw his funds, no matter what the sequencer does.*

#### Instantaneity

Alice signs a transaction and sends it to the sequencer.
The sequencer doesn't reply.
Now, to make sure the transaction goes through Alice uses the onchain queue.
*By looking at the queue, Bob knows his payment will be in the next block, assuming the sequencer stays online.*

So there is no guarantee of instantaneity. Alice expects an instantaneous response because the sequencer will have to pay gas fees to respond to an onchain queue. The fallback is confirmed at the speed of a normal L1 transaction.

### Graceful Shutdown

If the rollup is no longer profitable, or there is a far more efficient new design it would be useful to shut the rollup down safely. The exit game puts a lot of responsibilty on users to hold onto their receipts and make the appropriate claims. It's likely that some users will not recieve all the funds they're owed - perhaps they forgot about them, or they were on a long holiday during the claiming period etc.

Instead, there should be a function that lets the sequencer return all funds to their original owners on L1. This should not be immediately callable, as it breaks assumptions about instantaneity. Instead, the sequencer should have to declare shutdown well in advance, so that people have time to disable payments in their stores etc and move to the newer system.

This is essentially an upgrade mechanism that allows fully static and reliable contracts.