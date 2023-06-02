import { poseidonContract } from 'circomlibjs';
const abi = poseidonContract.generateABI(2);
const bytecode = poseidonContract.createCode(2);

console.log('abi', abi);
console.log('bytecode', bytecode);
