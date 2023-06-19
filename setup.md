# Repo navigation

- At the root, it has the structure of a foundry repo.
- All circuit specific code is in [./circuits](./circuits) directory. Circuits are written in circom.

To run and test smart contracts:
- forge test

For circuits:
- Run `yarn install` in [./circuits/circuits](./circuits/circuits) and [./circuits/scripts](./circuits/scripts).
- Install git submodule [circom-ecdsa@v0.0.1](https://github.com/0xPARC/circom-ecdsa/releases/tag/v0.0.1).
- Navigate to [./circuits/circuits/git_modules/circom-ecdsa](./circuits/circuits/git_modules/circom-ecdsa), and run `ln -s  ../../node_modules node_modules`.
  - Make sure to not commit the updated submodule.
- Navigate to [./circuits/scripts](./circuits/scripts) and run `gen_keys.sh`.
