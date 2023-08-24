use std::{collections::HashMap, env::current_dir, time::Instant};

use ff::PrimeField;
use nova_scotia::{
    circom::reader::load_r1cs, create_public_params, create_recursive_circuit, FileLocation, F1,
    G2, S1, S2,
};
use nova_snark::{traits::Group, CompressedSNARK};
use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Serialize, Deserialize, Debug)]
#[allow(non_snake_case)]
struct Withdraw {
    step_in: [String; 1],
    sender: Vec<String>,
    recipient: Vec<String>,
    leaf_coins: Vec<[String; 2]>,
    pathElements: Vec<Vec<String>>,
    pathIndices: Vec<Vec<String>>,
    r: Vec<Vec<String>>,
    s: Vec<Vec<String>>,
    msghash: Vec<Vec<String>>,
    pubkey: Vec<[Vec<String>; 2]>,
}

pub fn nova(iteration_count: usize) {
    let root = current_dir().unwrap();

    let circuit_file = root.join("circuits/build/compiled_circuit/withdraw.r1cs");
    let r1cs = load_r1cs(&FileLocation::PathBuf(circuit_file));
    let witness_generator_wasm =
        root.join("circuits/build/compiled_circuit/withdraw_js/withdraw.wasm");

    let withdraw_data: Withdraw =
        serde_json::from_str(include_str!("../inputs/withdraw.json")).unwrap();

    println!("json: {:?}", withdraw_data);

    let start_public_input = vec![F1::from_str_vartime(&withdraw_data.step_in[0]).unwrap()];

    let mut private_inputs = Vec::new();

    for i in 0..iteration_count {
        let mut private_input = HashMap::new();
        private_input.insert("sender".to_string(), json!(withdraw_data.sender[i]));
        private_input.insert("recipient".to_string(), json!(withdraw_data.recipient[i]));
        private_input.insert("leaf_coins".to_string(), json!(withdraw_data.leaf_coins[i]));
        private_input.insert(
            "pathElements".to_string(),
            json!(withdraw_data.pathElements[i]),
        );
        private_input.insert(
            "pathIndices".to_string(),
            json!(withdraw_data.pathIndices[i]),
        );
        private_input.insert("r".to_string(), json!(withdraw_data.r[i]));
        private_input.insert("s".to_string(), json!(withdraw_data.s[i]));
        private_input.insert("msghash".to_string(), json!(withdraw_data.msghash[i]));
        private_input.insert("pubkey".to_string(), json!(withdraw_data.pubkey[i]));

        private_inputs.push(private_input);
    }
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
    // println!("Verifying a RecursiveSNARK...");
    // println!("z0_primary: {:?}", start_public_input);
    // println!("z0_secondary: {:?}", z0_secondary);
    // let start = Instant::now();
    // let res = recursive_snark.verify(
    //     &pp,
    //     iteration_count,
    //     start_public_input.clone(),
    //     z0_secondary.clone(),
    // );
    // println!(
    //     "RecursiveSNARK::verify: {:?}, took {:?}",
    //     res,
    //     start.elapsed()
    // );
    // assert!(res.is_ok());

    // // produce a compressed SNARK
    // println!("Generating a CompressedSNARK using Spartan with IPA-PC...");
    // let start = Instant::now();
    // let (pk, vk) = CompressedSNARK::<_, _, _, _, S1, S2>::setup(&pp).unwrap();
    // let res = CompressedSNARK::<_, _, _, _, S1, S2>::prove(&pp, &pk, &recursive_snark);
    // println!(
    //     "CompressedSNARK::prove: {:?}, took {:?}",
    //     res.is_ok(),
    //     start.elapsed()
    // );
    // assert!(res.is_ok());
    // let compressed_snark = res.unwrap();

    // // verify the compressed SNARK
    // println!("Verifying a CompressedSNARK...");
    // println!("z0_primary: {:?}", start_public_input);
    // println!("z0_secondary: {:?}", z0_secondary);
    // let start = Instant::now();
    // let res = compressed_snark.verify(
    //     &vk,
    //     iteration_count,
    //     start_public_input.clone(),
    //     z0_secondary,
    // );
    // println!(
    //     "CompressedSNARK::verify: {:?}, took {:?}",
    //     res.is_ok(),
    //     start.elapsed()
    // );
    // assert!(res.is_ok());
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
