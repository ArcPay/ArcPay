# Altitude

Altitude is a payment validium with a fully trustless escape hatch. Users hold proofs that let them claim their coins during shutdown without relying on any external party. This enables arbitrary scaling with near L1 level security.

During shutdown, users have a month to prove ownership of their tokens. Newer proofs invalidate older proofs for the same tokens and every token is numbered. To get full self custody of their tokens, users need an ownership proof from the operator.

During normal operation, censorship resistance is guaranteed by onchain forcing. Users can force the operator to include their transaction, or return an ownership proof, and the operator must respond or their stake is slashed and the validium is shut down. The operator should address users' needs offchain to avoid gas costs. The operator is slashed if they don't regularly update the state.

Promises from the operator are a form of instant payment. If the promise is broken the operator is slashed. A user can show a promise was broken using an ownership proof. Promises don't have trustless finality because the validum could shut down. Finality happens when the user has an ownership proof for a state root that is finalised on L1.

## Background

Payments are a huge market that, if conquered, could make Eth a true money. Visa alone settles over [\$1T per month](https://bit.ly/3p5Q7pL). By using cryptoeconomics instead of underwriting transactions, we can undercut existing payment providers, while offering far stronger security to users.

Recently, L2s have been built on top of blockchains to minimse fees while inheriting security from the underlying blockchain. Strong L2s, like rollups with onchain calldata are limited by Ethereum's data throughput. Only state channel networks and rollups with DA (data availability) proofs currently allow arbitrary data scaling, which is necessary for low fees, but both make substantial security tradeoffs. We present a new L2 called Altitude, which combines their benefits.

|                | State Channels    | DA Rollup    | Altitude        |
| -----------    | -----------       | -----------  | -----------     |
| Escape Hatch   | ✅ Individual      | ❌ m-of-n    | ✅ Individual   |
| Finality       | ✅ Instant         | ❌ L1        | 🦺 Instant*     |
| Capital Lockup | ❌ O(throughput)   | ✅ O(1)      | ✅ O(1)         |
| Payment Limit  | ❌ Channel Balance | ✅ None      | ✅ None         |
| Theft Checkup  | ❌ ~Daily.         | ✅ Never     | 🦺 ~Monthly     |

<sup>*assuming the L2 doesn't shut down</sup>

# Shutdown

Altitude has to follow a variety of rules during normal operation to ensure censorship resistance and safety. If it violates any of these rules the validium is shut down. Shutdown freezes the state, fully slashes the operator's stake, and initiates the shutdown sequence.

## Escape Hatch

An escape hatch is a method of retrieving money from a system that has shut down. In Altitude, the escape hatch is trustless - users don't have to trust anyone to keep their money safe.

### Ownership Proofs

Validiums use onchain proofs and state roots to prove that offchain computation is done correctly. Altitude's state is a Merkle tree of UTXOs. To update the state, the operator must provide a ZKP that takes the old state root, validates and applies a set of transactions, and outputs the new state.

State roots are stored onchain and are available even if the validium shuts down. Ownership proofs are Merkle proofs for data in the UTXO tree. So the chain can verify claims like "X owned Y coins at time t."

### Claiming and Resolution

Once the rollup is shutdown, users have one month to claim their coins. Users post the whole ownership proof as calldata to the claiming contract, which just adds the proof to a cheap accumulator like a [binary hash chain](https://en.wikipedia.org/wiki/Hash_chain#Binary_hash_chains) to minimise gas costs. Once the claiming period is over, a resolver posts a ZKP which addresses every ownership proof in the accumulator, checking that the Merkle proof is valid, the state root is real, and resolving any conflicting claims. In case of a conflict, the later owner wins. The resolver ZKP simply posts the root of all the owners, who can now retrieve their money when they want.

Anyone can be a resolver, as the resolution proof can be constructed from onchain data. The resolver is paid a small fee for their efforts. The fee increases gradually over time to ensure that resolution eventually happens at a minimal cost.

### Scalable Claiming

Individually claiming each set of coins doesn't work at scale because the cost to retrieve each is quite high, and the gas price would spike. This makes the "trustless escape hatch" a fairly empty promise. Several solutions are discussed [here](https://hackmd.io/FYaYOZfQQr-Urw-c_KORrg), and the ultimate solution involves shuffling and escape pods. Escape pods are a way for users in a contiguous area to claim their coins together, and shuffling is a way to force the operator to tidy a particular set of coins into a contiguous area.

However, both shuffling and escape pods are quite complex, and will not be implemented in version 1. Users of version 1 should be aware of this risk and act accordingly (by maintaining tidy and valuable claims, or not holding much money in the system). Since it's not really trustless, version 1 relies somewhat on the benevolence and competence of the operator not to shut down, or to at least shut down gracefully.

## Graceful Shutdown

### Averting the Claim Game

If the operator is found to be in violation of their responsibilities and the validium is shut down, the operator has a period before claiming to gracefully shut down. The operator provides a proof of all the owners in the final state, and sends them their money. The operator is still slashed, but that slashed money can be put towards gas costs for distributing the tokens. This avoids the expensive and error prone claiming process.

### Upgrades

The smart contracts forming Altitude are not upgradable for security reasons. However, after a notice period, the operator can move the money and state to an entirely different set of contracts. First the operator deploys the v2 contracts with no restrictions, then the operator can specify an upgrade date several months in the future along with the v2 contract address. When the upgrade date arrives, the remaining money in v1 is sent to v2 via L1, and the final state of v1 is read by v2.

Even if an upgrade is planned, the validium can go into shutdown which cancels the upgrade. This form of upgradability doesn't require any additional vigilance by users, as they already have to check the chain monthly. It's prudent to make the minimum notice period several months to allow the new contracts to be widely audited and let people exit v1 gradually. This form of upgrades is not good for time sensitive upgrades like hotfixing vulnerabilities, as the vulnerability will probably be discovered and exploited by an attacker during the notice period.

# Normal Operation

The operator is subject to several rules during normal operation that enable censorship resistance, instant transactions, and the trustless escape hatch. . Namely, the operator:

- Must include onchain transactions
- Must honour promises to include transactions
- Must consistently update the state
- Must return ownership proofs

If these rules are broken, the validium is shutdown and users retrieve their money [as explained above](#Shutdown).

## Instant Payments

### Forced Inclusion

Having a centralised operator is crucial for instant transactions. To make promises about future payments, the operator needs to know the future state in advance without worrying about others altering it. However, users need to be able to send transactions permisionlessly to circumvent censorship by the operator.

Some rollups implement censorship resistance by decentralising the operator, but we need a centralised operator for instant transactions and data scaling. Some rollups use privacy to make targetted censorship impossible. While privacy [may be possible](https://hackmd.io/5FJzfDgJS3OT0RmwOmbfqQ) for Altitude, it is quite complex. Instead, we rely on `force_include`. Forced transactions are "locked in" onchain for a few blocks before they're included so the operator can read them before making promises about the future state. The operator must prove they've included all forced transactions to update the state.

<figure>
  <img src="https://i.imgur.com/wT2pNnS.jpg" alt="Diagram that resembles livestock pen illustrating how transactions are held in containers until they're included.">
  <figcaption><em>Initially, the operator can make promises about blocks <code>n</code> and <code>n+1</code>. After proving the state transition for block <code>n</code>, they can make promises about blocks <code>n+1</code> and <code>n+2</code>.</em></figcaption>
</figure>

If the operator refuses to update the state they are slashed for their entire stake. This achieves censorship resistance in that, during normal operation, users can force any transaction regardless of how much the operator doesn't want to include it. In the worst case, the operator can choose to shut down the validium to censor the transaction, but the user can still return their funds to the ~trustless L1.

### Offchain Payments

We use the onchain queue if the operator is censoring us, but in the cooperative case we send the transaction to the operator offchain, who includes it in the next state, skipping the queue.

Due to locking in `force_include`, the operator can calculate the state up to `k` blocks in the future. Therefore, the operator can promise to execute unforced transactions without fear that the user will invalidate them by forcing a double spend. That means the operator can safely risk their entire stake on a promise like "Bob will have tokens 1-100 in block 10."

Suppose Alice is buying an orange from Bob. She sends her transaction directly to the operator, who signs it, promising that the tokens will go to Bob in block `123`. This is called the receipt. Alice gives the receipt to Bob, who takes it as a strong guarantee of payment, and gives the orange to Alice.

![](https://i.imgur.com/EtxFtM9.jpg)




Bob holds on to the receipt until block `123`, when he asks the operator to prove that his tokens are included. If the operator doesn't respond, he takes the receipt onchain, and if the prover can't prove that he tokens are included, the operator is slashed and Bob earns a reward. To prove that the promise was fulfilled, the operator provides an [ownership proof](#Ownership-Proofs), which Bob holds in case the validium shuts down.

![](https://i.imgur.com/JV9DBUA.jpg)

<!-- TODO: try add a symbol for a Merkle proof beside the proof -->

## Finality guarantees

Soft finality is when we can be sure that a transaction will be included assuming that the validium doesn't shut down. Trustless finality is when we know the outputs of a transaction can be retrived regardless of how the operator or anyone else acts.

### Cooperative

<!-- TODO: draw diagrams for these -->

Alice signs a transaction and sends it to the operator.
The operator returns a receipt signing her transaction.
Alice gives the transaction to Bob.
*Bob payment has soft finality*
Bob waits until the next block of L2 transactions.
Bob asks the operator for a proof that his transaction is included in the most recent escape pod.
The operator returns the proof.
*Bob's payment has trustless finality*

### Uncooperative

Alice signs a transaction and sends it to the operator.
The operator doesn't reply.
Now, to make sure the transaction goes through Alice uses the onchain queue.
*Bob's payment has soft finality*
The payment is eventually included in a block.
Bob asks the operator for an ownership proof.
The operator doesn't respond.
Bob requests an ownership proof onchain.
The operator responds onchain.
*Bob's payment has trustless finality.*

Note, the uncooperative case does not have instant payments. Alice expects an instantaneous response because the operator will have to pay gas fees to respond to an onchain queue. The fallback requires several L1 transactions, making it slower than L1.
