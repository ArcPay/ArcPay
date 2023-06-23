use async_graphql::{Context, Object, Schema};
use async_graphql::{EmptySubscription};
use pmtree::{MerkleTree, Hasher};
use std::sync::Arc;
use futures::lock::Mutex;

use crate::merkle::{MemoryDB, MyPoseidon};
pub(crate) type ServiceSchema = Schema<QueryRoot, MutationRoot, EmptySubscription>;

pub(crate) struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn root(&self, ctx: &Context<'_>) -> Vec<u8> {
        let mt = ctx.data_unchecked::<SyncMerkle>().lock().await;
        MyPoseidon::serialize(mt.root())
    }
}

type SyncMerkle = Arc<Mutex<MerkleTree::<MemoryDB, MyPoseidon>>>;
pub(crate) struct MutationRoot;

#[Object]
impl MutationRoot {
    async fn insert(&self, ctx: &Context<'_>, address: Vec<u8>, low_coin: Vec<u8>, high_coin: Vec<u8>) -> bool {
        let mut mt = ctx.data_unchecked::<SyncMerkle>().lock().await;
        let hash = MyPoseidon::hash(&[MyPoseidon::deserialize(address), MyPoseidon::deserialize(low_coin), MyPoseidon::deserialize(high_coin)]);
        mt.update_next(hash).unwrap();
        true
    }
}
