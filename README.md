# circom-zkvm

Educational Circom implementation of the stack-based zkVM described in the RareSkills article [How a ZKVM Works](https://rareskills.io/post/zkvm).

## VM model

The VM uses fixed-width instructions: every instruction is two field elements, `[opcode, arg]`. Only `PUSH` consumes `arg`; the other opcodes ignore it so the program counter always advances by two cells.

| Opcode | Value | Effect |
| --- | ---: | --- |
| `NOP` | `0` | Leaves the stack unchanged. |
| `PUSH` | `1` | Pushes `arg` onto the stack. |
| `ADD` | `2` | Pops the top two stack values and pushes their field sum. |
| `MUL` | `3` | Pops the top two stack values and pushes their field product. |

The circuit is parameterized by a fixed instruction count `n`. The checked `main` component uses `ZKVM(5)`, so `instr` has ten cells. `steps` must be in `1..n`, and `out` is the bottom stack value after exactly that many instructions. Shorter programs should be padded with `NOP`.

## What is constrained

- Every opcode must be one of `NOP`, `PUSH`, `ADD`, or `MUL`.
- The first opcode cannot be `ADD` or `MUL`.
- `ADD` and `MUL` require at least two stack values, closing the arithmetic-underflow case that an educational implementation can otherwise miss.
- `PUSH` cannot write past the fixed stack capacity.
- `steps` must select exactly one executed row.
- Stack copies, pushes, sums, products, stack-pointer transitions, and the public `out` are all constrained.

`sp` and `stack` are circuit outputs to make the trace inspectable in tests. For a privacy-preserving proof, expose only `out` and any public program inputs you actually need.

## Setup

```bash
npm install
```

## Test

```bash
npm test
```

The tests compile the circuit with `circom_tester`, compare valid executions against the JavaScript reference VM in `src/vm.js`, exhaustively check all 1,024 opcode shapes for the 5-step main circuit, and assert that invalid opcodes, arithmetic underflow, and invalid `steps` do not satisfy the circuit.

## Compile

```bash
npm run compile
```

An article-style input is available at `examples/article-program.json`:

```json
{
  "instr": [1, 3, 1, 6, 1, 2, 3, 0, 3, 0],
  "steps": 5
}
```

It computes `3 * (6 * 2) = 36` in the default Circom field.
