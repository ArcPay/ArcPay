use crate::nova::{nova, NovaInput};
use circuit_input_macro::NovaRoundInput;
use circuit_input_macro_derive::NovaRoundInput;
use ff::PrimeField;
use nova_scotia::{circom::reader::load_r1cs, FileLocation, F1};
use pasta_curves::Fq;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::HashMap, env::current_dir};

#[derive(Serialize, Deserialize, Debug, Clone)]
#[allow(non_snake_case)]
struct Filter {
    step_in: [String; 5],
    private_inputs: Vec<FilterRound>,
}

impl NovaInput for Filter {
    fn initial_inputs(&self) -> Vec<Fq> {
        vec![
            F1::from_str_vartime(&self.step_in[0]).unwrap(),
            F1::from_str_vartime(&self.step_in[1]).unwrap(),
        ]
    }

    fn round_inputs(&self) -> Vec<HashMap<String, Value>> {
        self.private_inputs
            .iter()
            .map(|v| v.circuit_input())
            .collect()
    }
}

#[derive(Serialize, Deserialize, Debug, Clone, NovaRoundInput)]
#[allow(non_snake_case)]
struct FilterRound {
    // advice
    next_claim_chain: [String; 2],
    history_pathElements: Vec<String>, // history_depth length Vec, TODO: use array and pull from global constants
    state_root: String,
    filtered_pathElements: Vec<String>, // filtered_depth length Vec, TODO: use array and pull from global constants

    // claim
    address: String,                 // 160 bits
    first_coin: String,              // coin_bits bits
    last_coin: String,               // coin_bits bits
    block_number: String,            // history_depth bits
    state_pathElements: Vec<String>, // state_depth length Vec, TODO: use array and pull from global constants
    state_pathIndex: String,         // state_depth bits
}

pub fn filter(iteration_count: usize) {
    let root = current_dir().unwrap();

    let circuit_file = root.join("circuits/build/compiled_circuit/filter.r1cs");
    let r1cs = load_r1cs(&FileLocation::PathBuf(circuit_file));
    let witness_generator_wasm = root.join("circuits/build/compiled_circuit/filter_js/filter.wasm");

    let filter_data: Filter = serde_json::from_str(include_str!("../inputs/filter.json")).unwrap();
    nova(iteration_count, r1cs, filter_data, witness_generator_wasm);
}

#[cfg(test)]
mod tests {
    use super::*;
    // use std::env;
    #[test]
    fn test_nova() {
        filter(2);
    }
}
