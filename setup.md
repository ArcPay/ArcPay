# Repo navigation

- At the root, it has the structure of a foundry repo.
- All circuit specific code is in [./circuits](./circuits) directory. Circuits are written in circom.

To run and test smart contracts:
- forge test

For circuits:
- Run `yarn install` in [./circuits/circuits](./circuits/circuits) and [./circuits/scripts](./circuits/scripts).
- Navigate to [./circuits/scripts](./circuits/scripts) and run `gen_keys.sh`.

## Notes
Efficient ECDSA circuits:

Since Personae Labs haven't published their contracts on npm, we have directly copied them from commit [3899bfbfe1e4ab296d5e4bd0aede2aa54b6044f4](https://github.com/personaelabs/efficient-zk-ecdsa/tree/3899bfbfe1e4ab296d5e4bd0aede2aa54b6044f4).
