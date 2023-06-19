# Repo navigation

- At the root, it has the structure of a foundry repo.
- All circuit specific code is in [./circuits](./circuits) directory. Circuits are written in circom.

To run and test smart contracts:
- forge install
- forge test

For circuits:
- Run `yarn install` in [./circuits/circuits](./circuits/circuits) and [./circuits/scripts](./circuits/scripts).
- Navigate to [./circuits/scripts](./circuits/scripts) and run `gen_keys.sh`.