const assert = require("assert");
const path = require("path");
const { before, describe, it } = require("node:test");
const wasmTester = require("circom_tester").wasm;
const { FIELD_MODULUS, OPCODES, circuitInput, execute } = require("../src/vm");

const CIRCUIT_PATH = path.join(__dirname, "..", "circuits", "zkvm.circom");
const MAX_STEPS = 5;

async function expectValid(circuit, instr, steps) {
  const expected = execute(instr, steps, MAX_STEPS);
  const witness = await circuit.calculateWitness(circuitInput(instr, steps), true);
  await circuit.checkConstraints(witness);
  await circuit.assertOut(witness, {
    out: expected.out.toString(),
    sp: expected.sp.map((value) => value.toString()),
    stack: expected.stack.map((row) => row.map((value) => value.toString())),
  });
}

async function expectInvalid(circuit, instr, steps) {
  await assert.rejects(async () => {
    const witness = await circuit.calculateWitness(circuitInput(instr, steps), true);
    await circuit.checkConstraints(witness);
  });
}

describe("ZKVM", function () {
  let circuit;

  before(async function () {
    circuit = await wasmTester(CIRCUIT_PATH);
  });

  it("matches the article-style multiplication program", async function () {
    await expectValid(circuit, [
      OPCODES.PUSH, 3,
      OPCODES.PUSH, 6,
      OPCODES.PUSH, 2,
      OPCODES.MUL, 0,
      OPCODES.MUL, 0,
    ], 5);
  });

  it("returns the stack bottom after the requested number of steps", async function () {
    const instr = [
      OPCODES.PUSH, 3,
      OPCODES.PUSH, 6,
      OPCODES.PUSH, 2,
      OPCODES.MUL, 0,
      OPCODES.MUL, 0,
    ];

    await expectValid(circuit, instr, 1);
    await expectValid(circuit, instr, 4);
    await expectValid(circuit, instr, 5);
  });

  it("supports addition, multiplication, and NOP padding", async function () {
    await expectValid(circuit, [
      OPCODES.PUSH, 7,
      OPCODES.PUSH, 11,
      OPCODES.ADD, 0,
      OPCODES.NOP, 12345,
      OPCODES.NOP, 67890,
    ], 5);
  });

  it("uses Circom field arithmetic", async function () {
    await expectValid(circuit, [
      OPCODES.PUSH, FIELD_MODULUS - 1n,
      OPCODES.PUSH, 2,
      OPCODES.ADD, 0,
      OPCODES.PUSH, 3,
      OPCODES.MUL, 0,
    ], 5);
  });

  it("rejects invalid opcodes", async function () {
    await expectInvalid(circuit, [
      OPCODES.PUSH, 1,
      9, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ], 5);
  });

  it("rejects arithmetic stack underflow", async function () {
    await expectInvalid(circuit, [
      OPCODES.PUSH, 1,
      OPCODES.ADD, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ], 2);
  });

  it("rejects steps outside the fixed program", async function () {
    const instr = [
      OPCODES.PUSH, 1,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
      OPCODES.NOP, 0,
    ];

    await expectInvalid(circuit, instr, 0);
    await expectInvalid(circuit, instr, 6);
  });

  it("matches or rejects every opcode shape for the fixed program size", async function () {
    const opcodes = [OPCODES.NOP, OPCODES.PUSH, OPCODES.ADD, OPCODES.MUL];
    const args = [5, 7, 11, 13, 17];
    const totalPrograms = opcodes.length ** MAX_STEPS;

    for (let programIndex = 0; programIndex < totalPrograms; programIndex++) {
      let remaining = programIndex;
      const instr = [];

      for (let step = 0; step < MAX_STEPS; step++) {
        instr.push(opcodes[remaining % opcodes.length], args[step]);
        remaining = Math.floor(remaining / opcodes.length);
      }

      try {
        execute(instr, MAX_STEPS, MAX_STEPS);
        await expectValid(circuit, instr, MAX_STEPS);
      } catch (error) {
        await expectInvalid(circuit, instr, MAX_STEPS);
      }
    }
  });
});
