use std::{clone, collections::HashMap, env::current_dir, time::Instant};

use ff::PrimeField;
use nova_scotia::{
    circom::reader::load_r1cs, create_public_params, create_recursive_circuit, FileLocation, F1,
    G2, S1, S2,
};
use nova_snark::{traits::Group, CompressedSNARK};
use serde::{Deserialize, Serialize};
use serde_json::json;
use serde_json::Value;

#[derive(Serialize, Deserialize, Debug, Clone)]
#[allow(non_snake_case)]
struct Mint {
    step_in: [String; 2],
    private_inputs: Vec<MintRound>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
#[allow(non_snake_case)]
struct MintRound {
    sender: String,
    recipient: String,
    leaf_coins: [String; 2],
    mintPathElements: Vec<String>,
    mintPathIndices: Vec<String>,
    pathElements: Vec<String>,
    pathIndices: Vec<String>,
}

impl MintRound {
    fn circuit_inputs(&self) -> HashMap<String, Value> {
        let mut h = HashMap::new();
        h.insert("sender".to_string(), json!(self.sender));
        h.insert("recipient".to_string(), json!(self.recipient));
        h.insert("leaf_coins".to_string(), json!(self.leaf_coins));
        h.insert("mintPathElements".to_string(), json!(self.mintPathElements));
        h.insert("mintPathIndices".to_string(), json!(self.mintPathIndices));
        h.insert("pathElements".to_string(), json!(self.pathElements));
        h.insert("pathIndices".to_string(), json!(self.pathIndices));
        h
    }
}

pub fn nova(iteration_count: usize) {
    let root = current_dir().unwrap();

    let circuit_file = root.join("circuits/build/compiled_circuit/mint.r1cs");
    let r1cs = load_r1cs(&FileLocation::PathBuf(circuit_file));
    let witness_generator_wasm = root.join("circuits/build/compiled_circuit/mint_js/mint.wasm");

    let mint_data: Mint = serde_json::from_str(include_str!("../inputs/mint.json")).unwrap();

    println!("json: {:?}", mint_data);

    let start_public_input = vec![
        F1::from_str_vartime(&mint_data.step_in[0]).unwrap(),
        F1::from_str_vartime(&mint_data.step_in[1]).unwrap(),
    ];

    let private_inputs = mint_data
        .private_inputs
        .iter()
        .map(|v| v.circuit_inputs())
        .collect();

    dbg!(&private_inputs);

    let pp = create_public_params(r1cs.clone());

    println!(
        "Number of constraints per step (primary circuit): {}",
        pp.num_constraints().0
    );
    println!(
        "Number of constraints per step (secondary circuit): {}",
        pp.num_constraints().1
    );

    println!(
        "Number of variables per step (primary circuit): {}",
        pp.num_variables().0
    );
    println!(
        "Number of variables per step (secondary circuit): {}",
        pp.num_variables().1
    );

    println!("Creating a RecursiveSNARK...");
    let start = Instant::now();
    let recursive_snark = create_recursive_circuit(
        FileLocation::PathBuf(witness_generator_wasm),
        r1cs,
        private_inputs,
        start_public_input.clone(),
        &pp,
    )
    .unwrap();
    println!("RecursiveSNARK creation took {:?}", start.elapsed());

    // TODO: empty?
    let z0_secondary = vec![<G2 as Group>::Scalar::zero()];

    // verify the recursive SNARK
    println!("Verifying a RecursiveSNARK...");
    println!("z0_primary: {:?}", start_public_input);
    println!("z0_secondary: {:?}", z0_secondary);
    let start = Instant::now();
    let res = recursive_snark.verify(
        &pp,
        iteration_count,
        start_public_input.clone(),
        z0_secondary.clone(),
    );
    println!(
        "RecursiveSNARK::verify: {:?}, took {:?}",
        res,
        start.elapsed()
    );
    assert!(res.is_ok());

    // produce a compressed SNARK
    println!("Generating a CompressedSNARK using Spartan with IPA-PC...");
    let start = Instant::now();
    let (pk, vk) = CompressedSNARK::<_, _, _, _, S1, S2>::setup(&pp).unwrap();
    let res = CompressedSNARK::<_, _, _, _, S1, S2>::prove(&pp, &pk, &recursive_snark);
    println!(
        "CompressedSNARK::prove: {:?}, took {:?}",
        res.is_ok(),
        start.elapsed()
    );
    assert!(res.is_ok());
    let compressed_snark = res.unwrap();

    // verify the compressed SNARK
    println!("Verifying a CompressedSNARK...");
    println!("z0_primary: {:?}", start_public_input);
    println!("z0_secondary: {:?}", z0_secondary);
    let start = Instant::now();
    let res = compressed_snark.verify(
        &vk,
        iteration_count,
        start_public_input.clone(),
        z0_secondary,
    );
    println!(
        "CompressedSNARK::verify: {:?}, took {:?}",
        res.is_ok(),
        start.elapsed()
    );
    assert!(res.is_ok());
}

#[cfg(test)]
mod tests {
    use super::*;
    // use std::env;
    #[test]
    fn test_nova() {
        nova(2);
    }
}
