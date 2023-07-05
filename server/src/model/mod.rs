use async_graphql::{Context, Object, SimpleObject, Schema, EmptySubscription, InputObject};
use pmtree::{MerkleTree, Hasher};
use rln::circuit::Fr;
use std::sync::Arc;
use futures::lock::Mutex;
use secp256k1::{Secp256k1, Message, ecdsa, PublicKey};
use sha3::{Digest, Keccak256};

use crate::merkle::{MemoryDB, MyPoseidon};
pub(crate) type ServiceSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

pub(crate) struct QueryRoot;

#[Object]
impl QueryRoot {
    /// Returns the merkle root.
    /// Unsafe because it puts a lock on the merkle tree.
    async fn unsafe_root(&self, ctx: &Context<'_>) -> Vec<u8> {
        let mt = ctx.data_unchecked::<SyncMerkle>().lock().await;
        MyPoseidon::serialize(mt.root())
    }
}

type SyncMerkle = Arc<Mutex<MerkleTree::<MemoryDB, MyPoseidon>>>;
pub(crate) struct MutationRoot;

/// Leaf structure of the merkle tree.
/// `address` owns the coin range `[low_coin, high_coin]`.
#[derive(InputObject)]
struct Leaf {
    address: [u8; 20],
    low_coin: u64,
    high_coin: u64,
}

#[derive(SimpleObject)]
struct MerkleInfo {
    root: Vec<u8>,
    leaf: Vec<u8>,
}

#[Object]
impl MutationRoot {
    /// Insert a leaf in the merkle tree.
    async fn unsafe_insert(&self, ctx: &Context<'_>, leaf: Leaf) -> MerkleInfo {
        let mut mt = ctx.data_unchecked::<SyncMerkle>().lock().await;
        let mut address = vec![0u8; 12];
        address.extend_from_slice(&leaf.address);
        let hash = MyPoseidon::hash(&[MyPoseidon::deserialize(address), Fr::from(leaf.low_coin), Fr::from(leaf.high_coin)]);
        mt.update_next(hash).unwrap();
        MerkleInfo {
            root: MyPoseidon::serialize(mt.root()),
            leaf: MyPoseidon::serialize(mt.get(mt.leaves_set()-1).unwrap())
        }
    }

    /// Send coins `[leaf.low_coin, highest_coin_to_send]` to `receiver` from `leaf`.
    /// The send should be authorized by `leaf.address` through ECDSA signature `sig`.
    async fn unsafe_send(
        &self,
        ctx: &Context<'_>,
        leaf: Leaf,
        key: usize,
        highest_coin_to_send: u64,
        recipient: Vec<u8>,
        sig: [u8; 64],
        pubkey: [u8; 65],
    ) -> Vec<u8> {
        let mut mt = ctx.data_unchecked::<SyncMerkle>().lock().await;
        let hashed_leaf = mt.get(key).unwrap();

        let mut sender = vec![0u8; 12];
        sender.extend_from_slice(&leaf.address);
        assert_eq!(hashed_leaf, MyPoseidon::hash(&[MyPoseidon::deserialize(sender.clone()), Fr::from(leaf.low_coin), Fr::from(leaf.high_coin)]));

        let mut receiver = vec![0u8; 12];
        receiver.extend_from_slice(&recipient);
        let msg = MyPoseidon::hash(&[Fr::from(leaf.low_coin), Fr::from(leaf.high_coin), Fr::from(highest_coin_to_send), MyPoseidon::deserialize(receiver.clone())]);
        dbg!(MyPoseidon::serialize(msg));

        let secp = Secp256k1::verification_only();
        assert!(secp.verify_ecdsa(
            &Message::from_slice(&MyPoseidon::serialize(msg)).unwrap(),
            &ecdsa::Signature::from_compact(&sig).unwrap(),
            &PublicKey::from_slice(&pubkey).unwrap(),
        ).is_ok());

        assert_eq!(Keccak256::digest(&pubkey[1..65]).as_slice()[12..], leaf.address, "address doesn't match");

        mt.set(key, MyPoseidon::hash(&[MyPoseidon::deserialize(sender), Fr::from(highest_coin_to_send+1), Fr::from(leaf.high_coin)])).unwrap();
        mt.update_next(MyPoseidon::hash(&[MyPoseidon::deserialize(receiver), Fr::from(leaf.low_coin), Fr::from(highest_coin_to_send)])).unwrap();

        MyPoseidon::serialize(mt.root())
    }
}
