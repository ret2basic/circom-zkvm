# circom-zkvm

Educational Circom implementation of the stack-based zkVM described in the RareSkills article [How a ZKVM Works](https://rareskills.io/post/zkvm), now extended with SP1-inspired production boundaries.

## VM Model

The VM uses fixed-width instructions: every instruction is two field elements, `[opcode, arg]`. Only `PUSH` consumes `arg`; the other opcodes ignore it so the program counter always advances by two cells.

| Opcode | Value | Effect |
| --- | ---: | --- |
| `NOP` | `0` | Leaves the stack unchanged. |
| `PUSH` | `1` | Pushes `arg` onto the stack. |
| `ADD` | `2` | Pops the top two stack values and pushes their field sum. |
| `MUL` | `3` | Pops the top two stack values and pushes their field product. |
| `RETURN` | `4` | Halts execution and commits the bottom stack value as `out`. |

The production `main` component uses `ZKVMProduction(6)`, so `instr` has twelve cells. Programs must execute exactly one `RETURN`; rows after `RETURN` must be padded with `NOP`.

## SP1-Inspired Shape

- `instr` is private witness data.
- `programHash` is public and binds the proof to a fixed program identity.
- `out` is the public value committed by the VM at `RETURN`.
- [circuits/zkvm.circom](circuits/zkvm.circom) is the production entrypoint.
- [circuits/zkvm_trace.circom](circuits/zkvm_trace.circom) exposes trace outputs for tests and debugging.
- [docs/sp1-target-roadmap.md](docs/sp1-target-roadmap.md) describes the roadmap for moving this Circom project closer to SP1-style engineering.

## What Is Constrained

- Every opcode must be one of `NOP`, `PUSH`, `ADD`, `MUL`, or `RETURN`.
- `ADD` and `MUL` require at least two stack values.
- `PUSH` cannot write past the fixed stack capacity.
- `RETURN` requires at least one stack value.
- A valid program must return exactly once.
- After `RETURN`, only `NOP` padding is accepted.
- `programHash` must match the Poseidon chain hash of the instruction cells.
- Stack copies, pushes, sums, products, halt transitions, stack-pointer transitions, and the public `out` are all constrained.

The production circuit exposes only `out`. `sp`, `halted`, and `stack` are exposed only by the trace circuit for inspection.

## Setup

```bash
npm install
```

## Test

```bash
npm test
```

The tests compile the production and trace circuits with `circom_tester`, compare valid executions against the JavaScript reference VM in [src/vm.js](src/vm.js), check representative opcode shapes, and assert that invalid opcodes, arithmetic underflow, missing returns, bad post-return padding, and mismatched program hashes do not satisfy the circuit.

## Compile

```bash
npm run compile
```

To compile the debug trace circuit:

```bash
npm run compile:trace
```

An article-style input is available at [examples/article-program.json](examples/article-program.json):

```json
{
  "instr": [1, 3, 1, 6, 1, 2, 3, 0, 3, 0, 4, 0]
}
```

It computes `3 * (6 * 2) = 36` in the default Circom field, then commits `36` with `RETURN`.