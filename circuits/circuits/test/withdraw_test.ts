const path = require("path");
const wasm_tester = require("circom_tester").wasm;
const F1Field = require("ffjavascript").F1Field;
const Scalar = require("ffjavascript").Scalar;
exports.p = Scalar.fromString("21888242871839275222246405745257275088548364400416034343698204186575808495617");
const Fr = new F1Field(exports.p);

import { MerkleTree } from '../../scripts/util';
import { default as vmtree } from 'vmtree-sdk';


describe("Mux4 test", function () {
    this.timeout(100000);
    let circuit;

    this.beforeAll(async () => {
        circuit = await wasm_tester(path.join(__dirname, "circuits", "withdraw.circom"));
    });

    it("Should process a valid withdrawal", async () => {
        // Inputs
        let is_withdrawal = Fr.e(1);
        let is_valid_transaction = Fr.e(1);

        let recipient = Fr.e(123);
        let amount = Fr.e(100);

        const withdrawalTree = new MerkleTree({ hasher: vmtree.poseidon, levels: 2, zero: 0 });

        let withdrawalPathElements = withdrawalTree.proof(0);
        let withdrawalPathIndices;

        let bit_chain = Fr.e(-1);
        let root;
        let total_amount;
        let valid_withdrawal_count;

        // Expected ouputs
        let new_bit_chain;
        let new_root;
        let new_total_amount;
        let new_valid_withdrawal_count;

        const ct2 = [
            Fr.e("37"),
            Fr.e("47"),
        ];

        const w = await circuit.calculateWitness({ "selector": i }, true);
        await circuit.checkConstraints(w);
        await circuit.assertOut(w, { out: ct2[i] });
    });

    it("Should ignore non withdrawl", async () => { });

    it("Should udpate the bitchain but not the withdrawal outputs if it's an invalid withdrawal", async () => { });
});
