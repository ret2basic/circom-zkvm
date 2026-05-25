# circom-zkvm

A compact educational zkVM written in Circom. It starts from the stack machine in the RareSkills article [How a ZKVM Works](https://rareskills.io/post/zkvm), then adds the smallest set of features needed to feel like a real zkVM learning project: program identity, private inputs, public inputs, assertions, a Poseidon precompile, an opcode lookup table, recursion-friendly receipt hashes, a production circuit, a trace circuit, tests, and a tiny assembler.

The design goal is not to clone SP1 or RISC Zero. It is to make the architecture behind systems like SP1 small enough to inspect by hand.

## What It Proves

The production circuit proves this statement:

> I know a private instruction trace and private inputs such that the VM executes the program committed by `programHash`, reads the declared public inputs, halts with `RETURN`, produces public output `out`, and commits the public execution claim as `receiptHash`.

The production circuit hides the stack trace. The trace circuit exposes it for tests and learning. `receiptHash` is a Poseidon commitment to `programHash`, `publicInputs`, and `out`, so later aggregation or recursive-verifier experiments can work with a compact public claim.

## VM Model

Programs have exactly 10 instructions. Each instruction is two field elements, `[opcode, arg]`, so `instr` has 20 cells. Short programs are padded with `NOP`.

The VM has 4 private input slots and 4 public input slots.

| Opcode | Value | Effect |
| --- | ---: | --- |
| `NOP` | `0` | Leaves the stack unchanged. |
| `PUSH arg` | `1` | Pushes `arg` onto the stack. |
| `ADD` | `2` | Pops two values and pushes their field sum. |
| `MUL` | `3` | Pops two values and pushes their field product. |
| `RETURN` | `4` | Halts and commits the bottom stack value as `out`. |
| `READ_PRIVATE i` | `5` | Pushes private input slot `i`. |
| `READ_PUBLIC i` | `6` | Pushes public input slot `i`. |
| `ASSERT_EQ` | `7` | Pops two values and constrains them to be equal. |
| `POSEIDON2` | `8` | Pops two values and pushes `Poseidon(2)(left, right)`. |

All arithmetic is over the Circom BN254 scalar field.

## Important Files

- [circuits/zkvm_core.circom](circuits/zkvm_core.circom): VM transition constraints, stack semantics, input reads, assertions, Poseidon, and program hash.
- [circuits/opcode_lookup.circom](circuits/opcode_lookup.circom): fixed opcode lookup table that maps each opcode to semantic flags.
- [circuits/receipt.circom](circuits/receipt.circom): receipt hash and receipt aggregation primitives.
- [circuits/zkvm.circom](circuits/zkvm.circom): production entrypoint with public `programHash`, public `publicInputs`, public `out`, and public `receiptHash`.
- [circuits/zkvm_trace.circom](circuits/zkvm_trace.circom): debug entrypoint exposing `sp`, `halted`, `stack`, computed program hash, and computed receipt hash.
- [src/vm.js](src/vm.js): JavaScript reference VM used by tests.
- [src/assembler.js](src/assembler.js): small text-to-instruction assembler.
- [docs/mini-zkvm-book.md](docs/mini-zkvm-book.md): concept-by-concept explanation in a RareSkills-style teaching format.
- [docs/code-walkthrough.md](docs/code-walkthrough.md): file-by-file guide through the implementation.
- [docs/running-examples.md](docs/running-examples.md): commands and trace walkthroughs for runnable examples.
- [docs/completeness-checklist.md](docs/completeness-checklist.md): current feature completeness and explicit non-goals.
- [docs/sp1-target-roadmap.md](docs/sp1-target-roadmap.md): notes on how this learning project maps to SP1-style boundaries.

## Setup

```bash
npm install
```

## Test

```bash
npm test
```

The tests compile the production, trace, program-hash, opcode-table, receipt-hash, and receipt-aggregation circuits with `circom_tester`. They check valid executions against the JavaScript reference VM, verify receipt hashes, check order-sensitive receipt aggregation, and reject invalid opcodes, stack underflow, bad input indices, failed assertions, missing returns, post-return execution, and mismatched program hashes.

## Compile

```bash
npm run compile
npm run compile:trace
npm run compile:hash
npm run compile:opcode-table
npm run compile:receipt
npm run compile:aggregate
```

## Lookup And Receipts

Circom/R1CS does not provide native PLONK-style lookup arguments, so the opcode table is implemented as a fixed one-hot lookup: each opcode must match exactly one row in [circuits/opcode_lookup.circom](circuits/opcode_lookup.circom), and that row exposes flags such as `isPushLike`, `isPopOne`, `usesPoseidon`, and `returns`.

The receipt layer is a recursion-friendly public commitment, not a full recursive proof verifier. `receiptHash = H(programHash, publicInputs, out)` gives a compact claim for one VM execution, and [circuits/receipt_aggregate.circom](circuits/receipt_aggregate.circom) hashes two receipt hashes into one aggregate digest. A full recursive verifier would additionally verify prior proofs inside a circuit.

## Assemble Programs

```bash
npm run assemble -- examples/private-hash-claim.asm
```

Example assembly:

```text
READ_PRIVATE 0
READ_PRIVATE 1
POSEIDON2
READ_PUBLIC 0
ASSERT_EQ
PUSH 1
RETURN
```

This proves knowledge of private inputs `[1, 2]` whose Poseidon hash equals public input slot `0`, then returns `1`.

Ready-to-read examples live in [examples/article-program.asm](examples/article-program.asm), [examples/article-program.json](examples/article-program.json), [examples/field-arithmetic.asm](examples/field-arithmetic.asm), [examples/private-hash-claim.asm](examples/private-hash-claim.asm), and [examples/private-hash-claim.json](examples/private-hash-claim.json).

## Run Examples Through Circuits

```bash
npm run example -- examples/article-program.asm
npm run example -- examples/field-arithmetic.asm
npm run example -- examples/private-hash-claim.json
npm run example -- examples/article-program.asm examples/private-hash-claim.json
```

The runner executes the real Circom production and trace circuits with `circom_tester`, prints the trace, checks `programHash` / `receiptHash`, and aggregates two receipt hashes when two programs are provided. See [docs/running-examples.md](docs/running-examples.md) for a guided walkthrough.

`.asm` examples contain instructions only, so the runner uses `[0, 0, 0, 0]` for both private and public inputs. Use `.json` examples when a program needs nonzero `privateInputs` or `publicInputs`.