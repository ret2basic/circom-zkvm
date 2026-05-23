const assert = require("assert");
const path = require("path");
const { before, describe, it } = require("node:test");
const wasmTester = require("circom_tester").wasm;
const { FIELD_MODULUS, OPCODES, circuitInput, execute } = require("../src/vm");

const HASH_CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "program_hash.circom");
const PRODUCTION_CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "zkvm.circom");
const TRACE_CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "zkvm_trace.circom");
const MAX_STEPS = 6;

function instrInput(instr) {
  return {
    instr: instr.map((value) => value.toString()),
  };
}

async function getProgramHash(hashCircuit, instr) {
  const witness = await hashCircuit.calculateWitness(instrInput(instr), true);
  await hashCircuit.checkConstraints(witness);
  const output = await hashCircuit.getOutput(witness, { computedProgramHash: 1 });
  return output.computedProgramHash.toString();
}

async function expectValid(hashCircuit, productionCircuit, traceCircuit, instr) {
  const expected = execute(instr, MAX_STEPS);
  const programHash = await getProgramHash(hashCircuit, instr);

  const productionWitness = await productionCircuit.calculateWitness(circuitInput(instr, programHash), true);
  await productionCircuit.checkConstraints(productionWitness);
  await productionCircuit.assertOut(productionWitness, {
    out: expected.out.toString(),
  });

  const traceWitness = await traceCircuit.calculateWitness(instrInput(instr), true);
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

async function expectInvalid(hashCircuit, productionCircuit, instr, inputOverride = {}) {
  const programHash = await getProgramHash(hashCircuit, instr);
  const input = {
    ...circuitInput(instr, programHash),
    ...inputOverride,
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

  it("matches the article-style multiplication program with explicit RETURN", async function () {
    await expectValid(hashCircuit, productionCircuit, traceCircuit, [
      OPCODES.PUSH, 3,
      OPCODES.PUSH, 6,
      OPCODES.PUSH, 2,
      OPCODES.MUL, 0,
      OPCODES.MUL, 0,
      OPCODES.RETURN, 0,
    ]);
  });

  it("supports addition, multiplication, RETURN, and NOP padding", async function () {
    await expectValid(hashCircuit, productionCircuit, traceCircuit, [
      OPCODES.PUSH, 7,
      OPCODES.PUSH, 11,
      OPCODES.ADD, 0,
      OPCODES.RETURN, 0,
      OPCODES.NOP, 12345,
      OPCODES.NOP, 67890,
    ]);
  });

  it("uses Circom field arithmetic", async function () {
    await expectValid(hashCircuit, productionCircuit, traceCircuit, [
      OPCODES.PUSH, FIELD_MODULUS - 1n,
      OPCODES.PUSH, 2,
      OPCODES.ADD, 0,
      OPCODES.PUSH, 3,
      OPCODES.MUL, 0,
      OPCODES.RETURN, 0,
    ]);
  });

  it("rejects invalid opcodes", async function () {
    await expectInvalid(hashCircuit, productionCircuit, [
      OPCODES.PUSH, 1,
      9, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.RETURN, 0,
    ]);
  });

  it("rejects arithmetic stack underflow", async function () {
    await expectInvalid(hashCircuit, productionCircuit, [
      OPCODES.PUSH, 1,
      OPCODES.ADD, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.RETURN, 0,
    ]);
  });

  it("rejects RETURN on an empty stack", async function () {
    await expectInvalid(hashCircuit, productionCircuit, [
      OPCODES.RETURN, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ]);
  });

  it("rejects programs that never RETURN", async function () {
    await expectInvalid(hashCircuit, productionCircuit, [
      OPCODES.PUSH, 1,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ]);
  });

  it("rejects non-NOP instructions after RETURN", async function () {
    await expectInvalid(hashCircuit, productionCircuit, [
      OPCODES.PUSH, 1,
      OPCODES.RETURN, 0,
      OPCODES.PUSH, 2,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ]);
  });

  it("rejects mismatched program hashes", async function () {
    await expectInvalid(hashCircuit, productionCircuit, [
      OPCODES.PUSH, 1,
      OPCODES.RETURN, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ], { programHash: "123" });
  });

  it("matches or rejects representative opcode shapes with forced RETURN", async function () {
    const opcodes = [OPCODES.NOP, OPCODES.PUSH, OPCODES.ADD, OPCODES.MUL];
    const args = [5, 7, 11, 13];
    const totalPrograms = opcodes.length ** 4;

    for (let programIndex = 0; programIndex < totalPrograms; programIndex++) {
      let remaining = programIndex;
      const instr = [];

      for (let step = 0; step < 4; step++) {
        instr.push(opcodes[remaining % opcodes.length], args[step]);
        remaining = Math.floor(remaining / opcodes.length);
      }

      instr.push(OPCODES.RETURN, 0, OPCODES.NOP, 0);

      try {
        execute(instr, MAX_STEPS);
        await expectValid(hashCircuit, productionCircuit, traceCircuit, instr);
      } catch (error) {
        await expectInvalid(hashCircuit, productionCircuit, instr);
      }
    }
  });
});