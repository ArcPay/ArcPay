use pmtree::PmtreeErrorKind::DatabaseError;
use std::collections::HashMap;
use pmtree::{MerkleTree, DBKey, Value, PmtreeResult, DatabaseErrorKind, Database, Hasher};
use rln::{hashers::PoseidonHash, utils::{fr_to_bytes_le, bytes_le_to_fr}};
use hex_literal::hex;
use rln::circuit::Fr as Fp;

struct MemoryDB(HashMap<DBKey, Value>);
struct MyPoseidon(PoseidonHash);

#[derive(Default)]
struct MemoryDBConfig;

impl Database for MemoryDB {
    type Config = MemoryDBConfig;

    fn new(_db_config: MemoryDBConfig) -> PmtreeResult<Self> {
        Ok(MemoryDB(HashMap::new()))
    }

    fn load(_db_config: MemoryDBConfig) -> PmtreeResult<Self> {
        Err(DatabaseError(DatabaseErrorKind::CannotLoadDatabase))
    }

    fn get(&self, key: DBKey) -> PmtreeResult<Option<Value>> {
        Ok(self.0.get(&key).cloned())
    }

    fn put(&mut self, key: DBKey, value: Value) -> PmtreeResult<()> {
        self.0.insert(key, value);

        Ok(())
    }

    fn put_batch(&mut self, subtree: HashMap<DBKey, Value>) -> PmtreeResult<()> {
        self.0.extend(subtree.into_iter());

        Ok(())
    }
}

impl Hasher for MyPoseidon {
    type Fr = Fp;

    fn default_leaf() -> Self::Fr {
        Self::Fr::from(0)
    }


    fn serialize(value: Self::Fr) -> Value {
        fr_to_bytes_le(&value)
    }

    fn deserialize(value: Value) -> Self::Fr {
        bytes_le_to_fr(&value).0 // TODO: confirm if .1 is required
    }

    fn hash(input: &[Self::Fr]) -> Self::Fr {
        <PoseidonHash as utils::merkle_tree::Hasher>::hash(input)
    }
}

pub fn merkle() {
    let mut mt = MerkleTree::<MemoryDB, MyPoseidon>::new(2, MemoryDBConfig).unwrap();

    assert_eq!(mt.capacity(), 4);
    assert_eq!(mt.depth(), 2);

    mt.update_next(MyPoseidon::deserialize(hex!(
        "c1ba1812ff680ce84c1d5b4f1087eeb08147a4d510f3496b2849df3a73f5af95"
    ).to_vec()))
    .unwrap();

    dbg!(mt.root());
}
