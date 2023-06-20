#!/bin/bash

# Instructions:
# 1. Run `yarn install` in both circuits & scripts directories.

# High level steps:
# 1. Generates input for the circuit.
# 2. Compiles the circuit.
# 3. Generates a witness.
# 4. Generates a trusted setup.
# 5. Generates a proof.
# 6. Generates calldata for verifier contract.

set -e

# Download the powers of tau file from here: https://github.com/iden3/snarkjs#7-prepare-phase-2
# Move to directory specified below
PHASE1=../circuits/powers_of_tau/powersOfTau28_hez_final_14.ptau

# Relevant directories.
BUILD_DIR=../circuits/build
COMPILED_DIR=$BUILD_DIR/compiled_circuit
TRUSTED_SETUP_DIR=$BUILD_DIR/trusted_setup

PROOF_DIR=../circuits/proof_data

CIRCUIT_NAME=mint
CIRCUIT_PATH=../circuits/$CIRCUIT_NAME

if [ ! -d "$BUILD_DIR" ]; then
    echo "No build directory found. Creating build directory..."
    mkdir "$BUILD_DIR"
fi

if [ ! -d "$COMPILED_DIR" ]; then
    echo "No compiled directory found. Creating compiled circuit directory..."
    mkdir "$COMPILED_DIR"
fi

if [ ! -d "$TRUSTED_SETUP_DIR" ]; then
    echo "No trusted setup directory found. Creating trusted setup directory..."
    mkdir "$TRUSTED_SETUP_DIR"
fi

if [ ! -d "$PROOF_DIR" ]; then
    echo "No directory found for proof data. Creating a block's proof data directory..."
    mkdir "$PROOF_DIR"
fi

if [ ! -f "$COMPILED_DIR"/"$CIRCUIT_NAME".r1cs ]; then
    echo "**** COMPILING CIRCUIT $CIRCUIT_PATH.circom ****"
    echo $COMPILED_DIR
    start=`date +%s`
    echo circom "$CIRCUIT_PATH.circom" --O1 --r1cs --wasm --c --prime vesta --sym --output "$COMPILED_DIR"
    circom "$CIRCUIT_PATH.circom" --O1 --r1cs --wasm --c --prime vesta --sym --output "$COMPILED_DIR"
    end=`date +%s`
    echo "DONE ($((end-start))s)"
fi

# COMMENTING FROM HERE FOR NOT COMPATIBLE WITH NOVA SCOTIA CIRCOM

# echo "$COMPILED_DIR/${CIRCUIT_NAME}_0000.zkey"
# if [ ! -f "$COMPILED_DIR/${CIRCUIT_NAME}_0000.zkey" ]
# then
#     echo generating zkp proving and verifying keys!
#     snarkjs g16s \
# 		$COMPILED_DIR/$CIRCUIT_NAME.r1cs \
# 		../circuits/powers_of_tau/powersOfTau28_hez_final_14.ptau \
# 		$COMPILED_DIR/${CIRCUIT_NAME}_0000.zkey -v
#     echo ${CIRCUIT_NAME} groth16 setup complete!
# else
#     echo ${CIRCUIT_NAME} groth16 setup already complete!
# fi

# if [ ! -f "$COMPILED_DIR/${CIRCUIT_NAME}_final.zkey" ]
# then
#     snarkjs zkc \
# 		$COMPILED_DIR/${CIRCUIT_NAME}_0000.zkey $COMPILED_DIR/${CIRCUIT_NAME}_final.zkey -v \
# 		-e='vitaliks simple mixer'
#     echo ${CIRCUIT_NAME} contribution complete!
# else
#     echo ${CIRCUIT_NAME} contribution already complete!
# fi

# if [ ! -f "$COMPILED_DIR/${CIRCUIT_NAME}_verifier.json" ]
# then
#     snarkjs zkev \
# 		$COMPILED_DIR/${CIRCUIT_NAME}_final.zkey \
# 		$COMPILED_DIR/${CIRCUIT_NAME}_verifier.json
#     echo $TARGET verifier json exported!
# else
#     echo $TARGET verifier json already exported!
# fi

# if [ ! -f "$COMPILED_DIR/${CIRCUIT_NAME}_verifier.sol" ]
# then
# 	snarkjs zkesv \
# 		$COMPILED_DIR/${CIRCUIT_NAME}_final.zkey \
# 		$COMPILED_DIR/${CIRCUIT_NAME}_verifier.sol
#     echo $TARGET verifier template contract exported!
# else
#     echo $TARGET verifier template contract already exported!
# fi

# # Outputs calldata for the verifier contract.
# # TODO specify PROOF_DIR
# echo "****GENERATING CALLDATA FOR VERIFIER CONTRACT****"
# start=`date +%s`
# snarkjs zkey export soliditycalldata $PROOF_DIR/public.json "$PROOF_DIR"/proof.json > "$PROOF_DIR"/calldata.txt
# end=`date +%s`
# echo "DONE ($((end-start))s)"
