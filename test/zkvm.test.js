const assert = require("assert");
const path = require("path");
const { before, describe, it } = require("node:test");
const wasmTester = require("circom_tester").wasm;
const { assemble } = require("../src/assembler");
const { FIELD_MODULUS, OPCODES, circuitInput, execute } = require("../src/vm");

const HASH_CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "program_hash.circom");
const PRODUCTION_CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "zkvm.circom");
const TRACE_CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "zkvm_trace.circom");
const MAX_STEPS = 10;
const ZERO_PRIVATE_INPUTS = [0n, 0n, 0n, 0n];
const ZERO_PUBLIC_INPUTS = [0n, 0n, 0n, 0n];
const POSEIDON_1_2 = 7853200120776062878684798364095072458815029376092732009249414926327459813530n;

function instrInput(instr) {
  return {
    instr: instr.map((value) => value.toString()),
  };
}

function traceInput(instr, privateInputs, publicInputs) {
  return {
    ...instrInput(instr),
    privateInputs: privateInputs.map((value) => value.toString()),
    publicInputs: publicInputs.map((value) => value.toString()),
  };
}

function poseidon2ForTests(left, right) {
  if (left === 1n && right === 2n) {
    return POSEIDON_1_2;
  }

  throw new Error(`missing test Poseidon fixture for [${left}, ${right}]`);
}

async function getProgramHash(hashCircuit, instr) {
  const witness = await hashCircuit.calculateWitness(instrInput(instr), true);
  await hashCircuit.checkConstraints(witness);
  const output = await hashCircuit.getOutput(witness, { computedProgramHash: 1 });
  return output.computedProgramHash.toString();
}

async function expectValid(hashCircuit, productionCircuit, traceCircuit, instr, options = {}) {
  const privateInputs = options.privateInputs ?? ZERO_PRIVATE_INPUTS;
  const publicInputs = options.publicInputs ?? ZERO_PUBLIC_INPUTS;
  const expected = execute(instr, {
    maxSteps: MAX_STEPS,
    privateInputs,
    publicInputs,
    poseidon2: options.poseidon2,
  });
  const programHash = await getProgramHash(hashCircuit, instr);

  const productionWitness = await productionCircuit.calculateWitness(circuitInput(instr, privateInputs, publicInputs, programHash), true);
  await productionCircuit.checkConstraints(productionWitness);
  await productionCircuit.assertOut(productionWitness, {
    out: expected.out.toString(),
  });

  const traceWitness = await traceCircuit.calculateWitness(traceInput(instr, privateInputs, publicInputs), true);
  await traceCircuit.checkConstraints(traceWitness);
  await traceCircuit.assertOut(traceWitness, {
    out: expected.out.toString(),
    computedProgramHash: programHash,
    finalSp: expected.finalSp.toString(),
    halted: expected.halted.map((value) => value.toString()),
    sp: expected.sp.map((value) => value.toString()),
    stack: expected.stack.map((row) => row.map((value) => value.toString())),
  });
}

async function expectInvalid(hashCircuit, productionCircuit, instr, options = {}) {
  const privateInputs = options.privateInputs ?? ZERO_PRIVATE_INPUTS;
  const publicInputs = options.publicInputs ?? ZERO_PUBLIC_INPUTS;
  const programHash = await getProgramHash(hashCircuit, instr);
  const input = {
    ...circuitInput(instr, privateInputs, publicInputs, programHash),
    ...options.inputOverride,
  };

  await assert.rejects(async () => {
    const witness = await productionCircuit.calculateWitness(input, true);
    await productionCircuit.checkConstraints(witness);
  });
}

describe("ZKVM", function () {
  let hashCircuit;
  let productionCircuit;
  let traceCircuit;

  before(async function () {
    hashCircuit = await wasmTester(HASH_CIRCUIT_PATH);
    productionCircuit = await wasmTester(PRODUCTION_CIRCUIT_PATH);
    traceCircuit = await wasmTester(TRACE_CIRCUIT_PATH);
  });

  it("assembles and runs the article-style multiplication program", async function () {
    const instr = assemble(`
      PUSH 3
      PUSH 6
      PUSH 2
      MUL
      MUL
      RETURN
    `, { maxSteps: MAX_STEPS });

    await expectValid(hashCircuit, productionCircuit, traceCircuit, instr);
  });

  it("uses private and public inputs in normal field arithmetic", async function () {
    const instr = assemble(`
      READ_PRIVATE 0
      READ_PUBLIC 0
      ADD
      RETURN
    `, { maxSteps: MAX_STEPS });

    await expectValid(hashCircuit, productionCircuit, traceCircuit, instr, {
      privateInputs: [5n, 0n, 0n, 0n],
      publicInputs: [7n, 0n, 0n, 0n],
    });
  });

  it("proves a private Poseidon preimage against a public hash", async function () {
    const instr = assemble(`
      READ_PRIVATE 0
      READ_PRIVATE 1
      POSEIDON2
      READ_PUBLIC 0
      ASSERT_EQ
      PUSH 1
      RETURN
    `, { maxSteps: MAX_STEPS });

    await expectValid(hashCircuit, productionCircuit, traceCircuit, instr, {
      privateInputs: [1n, 2n, 0n, 0n],
      publicInputs: [POSEIDON_1_2, 0n, 0n, 0n],
      poseidon2: poseidon2ForTests,
    });
  });

  it("rejects a wrong public hash in the private preimage program", async function () {
    const instr = assemble(`
      READ_PRIVATE 0
      READ_PRIVATE 1
      POSEIDON2
      READ_PUBLIC 0
      ASSERT_EQ
      PUSH 1
      RETURN
    `, { maxSteps: MAX_STEPS });

    await expectInvalid(hashCircuit, productionCircuit, instr, {
      privateInputs: [1n, 2n, 0n, 0n],
      publicInputs: [123n, 0n, 0n, 0n],
    });
  });

  it("uses Circom field arithmetic", async function () {
    const instr = assemble(`
      PUSH ${FIELD_MODULUS - 1n}
      PUSH 2
      ADD
      PUSH 3
      MUL
      RETURN
    `, { maxSteps: MAX_STEPS });

    await expectValid(hashCircuit, productionCircuit, traceCircuit, instr);
  });

  it("rejects invalid opcodes", async function () {
    const instr = [
      OPCODES.PUSH, 1,
      99, 0,
      OPCODES.RETURN, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ];

    await expectInvalid(hashCircuit, productionCircuit, instr);
  });

  it("rejects stack underflow and empty returns", async function () {
    await expectInvalid(hashCircuit, productionCircuit, assemble(`
      PUSH 1
      ADD
      RETURN
    `, { maxSteps: MAX_STEPS }));

    await expectInvalid(hashCircuit, productionCircuit, assemble(`
      RETURN
    `, { maxSteps: MAX_STEPS }));
  });

  it("rejects out-of-range input reads", async function () {
    await expectInvalid(hashCircuit, productionCircuit, assemble(`
      READ_PRIVATE 4
      RETURN
    `, { maxSteps: MAX_STEPS }));

    await expectInvalid(hashCircuit, productionCircuit, assemble(`
      READ_PUBLIC 4
      RETURN
    `, { maxSteps: MAX_STEPS }));
  });

  it("rejects programs that never return or keep executing after return", async function () {
    await expectInvalid(hashCircuit, productionCircuit, assemble(`
      PUSH 1
    `, { maxSteps: MAX_STEPS }));

    await expectInvalid(hashCircuit, productionCircuit, assemble(`
      PUSH 1
      RETURN
      PUSH 2
    `, { maxSteps: MAX_STEPS }));
  });

  it("rejects mismatched program hashes", async function () {
    const instr = assemble(`
      PUSH 1
      RETURN
    `, { maxSteps: MAX_STEPS });

    await expectInvalid(hashCircuit, productionCircuit, instr, {
      inputOverride: { programHash: "123" },
    });
  });
});