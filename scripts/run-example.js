#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const wasmTester = require("circom_tester").wasm;
const { assemble } = require("../src/assembler");
const { OPCODE_NAMES } = require("../src/vm");

const MAX_STEPS = 10;
const INPUT_COUNT = 4;
const CIRCUITS_DIR = path.join(__dirname, "..", "circuits");
const ZERO_INPUTS = [0n, 0n, 0n, 0n];

function usage() {
  console.error("usage: node scripts/run-example.js <program.asm|program.json> [second-program.asm|json]");
  console.error("If two programs are provided, their receipt hashes are also aggregated.");
}

function toFieldArray(values, fallback, name) {
  const normalized = values === undefined ? fallback : values;
  if (!Array.isArray(normalized) || normalized.length !== INPUT_COUNT) {
    throw new Error(`${name} must contain ${INPUT_COUNT} values`);
  }

  return normalized.map((value) => BigInt(value));
}

function loadProgram(filePath) {
  const extension = path.extname(filePath);
  if (extension === ".asm") {
    const source = fs.readFileSync(filePath, "utf8");
    return {
      filePath,
      instr: assemble(source, { maxSteps: MAX_STEPS }).map(BigInt),
      privateInputs: ZERO_INPUTS,
      publicInputs: ZERO_INPUTS,
      privateInputsSource: ".asm files contain only instructions; default zero private inputs were used",
      publicInputsSource: ".asm files contain only instructions; default zero public inputs were used",
    };
  }

  if (extension === ".json") {
    const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!Array.isArray(parsed.instr) || parsed.instr.length !== 2 * MAX_STEPS) {
      throw new Error(`${filePath} must contain ${2 * MAX_STEPS} instruction cells`);
    }

    return {
      filePath,
      instr: parsed.instr.map((value) => BigInt(value)),
      privateInputs: toFieldArray(parsed.privateInputs, ZERO_INPUTS, "privateInputs"),
      publicInputs: toFieldArray(parsed.publicInputs, ZERO_INPUTS, "publicInputs"),
      privateInputsSource: parsed.privateInputs === undefined ? "privateInputs missing in JSON; default zeros were used" : "loaded from JSON privateInputs",
      publicInputsSource: parsed.publicInputs === undefined ? "publicInputs missing in JSON; default zeros were used" : "loaded from JSON publicInputs",
    };
  }

  throw new Error(`unsupported program file extension: ${extension}`);
}

function circuitInput(values) {
  return values.map((value) => value.toString());
}

function formatStack(row, sp) {
  const live = row.slice(0, Number(sp)).map((value) => value.toString());
  return `[${live.join(", ")}]`;
}

function instructionName(instr, step) {
  const opcode = Number(instr[2 * step]);
  const arg = instr[2 * step + 1];
  const name = OPCODE_NAMES[opcode] ?? `UNKNOWN_${opcode}`;

  if (name === "PUSH" || name === "READ_PRIVATE" || name === "READ_PUBLIC") {
    return `${name} ${arg}`;
  }

  return name;
}

async function getProgramHash(hashCircuit, instr) {
  const witness = await hashCircuit.calculateWitness({ instr: circuitInput(instr) }, true);
  await hashCircuit.checkConstraints(witness);
  const output = await hashCircuit.getOutput(witness, { computedProgramHash: 1 });
  return output.computedProgramHash.toString();
}

async function getReceiptHash(receiptCircuit, programHash, publicInputs, out) {
  const witness = await receiptCircuit.calculateWitness({
    programHash,
    publicInputs: circuitInput(publicInputs),
    out,
  }, true);
  await receiptCircuit.checkConstraints(witness);
  const output = await receiptCircuit.getOutput(witness, { receiptHash: 1 });
  return output.receiptHash.toString();
}

async function runProgram(program, circuits) {
  const programHash = await getProgramHash(circuits.hash, program.instr);
  const productionInput = {
    instr: circuitInput(program.instr),
    privateInputs: circuitInput(program.privateInputs),
    publicInputs: circuitInput(program.publicInputs),
    programHash,
  };

  const productionWitness = await circuits.production.calculateWitness(productionInput, true);
  await circuits.production.checkConstraints(productionWitness);
  const productionOutput = await circuits.production.getOutput(productionWitness, {
    out: 1,
    receiptHash: 1,
  });

  const expectedReceiptHash = await getReceiptHash(
    circuits.receipt,
    programHash,
    program.publicInputs,
    productionOutput.out.toString(),
  );

  if (expectedReceiptHash !== productionOutput.receiptHash.toString()) {
    throw new Error("receipt hash mismatch between production and receipt helper circuits");
  }

  const traceWitness = await circuits.trace.calculateWitness({
    instr: circuitInput(program.instr),
    privateInputs: circuitInput(program.privateInputs),
    publicInputs: circuitInput(program.publicInputs),
  }, true);
  await circuits.trace.checkConstraints(traceWitness);
  const traceOutput = await circuits.trace.getOutput(traceWitness, {
    out: 1,
    computedProgramHash: 1,
    computedReceiptHash: 1,
    finalSp: 1,
    sp: [MAX_STEPS + 1, 1],
    halted: [MAX_STEPS + 1, 1],
    stack: [MAX_STEPS, [MAX_STEPS, 1]],
  });

  if (traceOutput.computedProgramHash.toString() !== programHash) {
    throw new Error("trace circuit computed a different program hash");
  }

  if (traceOutput.computedReceiptHash.toString() !== productionOutput.receiptHash.toString()) {
    throw new Error("trace circuit computed a different receipt hash");
  }

  return {
    programHash,
    out: productionOutput.out.toString(),
    receiptHash: productionOutput.receiptHash.toString(),
    finalSp: traceOutput.finalSp.toString(),
    sp: traceOutput.sp.map((value) => value.toString()),
    halted: traceOutput.halted.map((value) => value.toString()),
    stack: traceOutput.stack.map((row) => row.map((value) => value.toString())),
  };
}

async function aggregateReceipts(aggregateCircuit, receiptHashes) {
  const witness = await aggregateCircuit.calculateWitness({ receiptHashes }, true);
  await aggregateCircuit.checkConstraints(witness);
  const output = await aggregateCircuit.getOutput(witness, { aggregateHash: 1 });
  return output.aggregateHash.toString();
}

function printProgramRun(program, result) {
  console.log(`\nProgram: ${program.filePath}`);
  console.log(`privateInputs: [${program.privateInputs.join(", ")}] (${program.privateInputsSource})`);
  console.log(`publicInputs:  [${program.publicInputs.join(", ")}] (${program.publicInputsSource})`);
  console.log(`programHash:   ${result.programHash}`);
  console.log(`out:           ${result.out}`);
  console.log(`receiptHash:   ${result.receiptHash}`);
  console.log(`finalSp:       ${result.finalSp}`);
  console.log("\nTrace:");
  console.log("step | instruction        | sp | halted | stack");
  console.log(`0    | initial            | ${result.sp[0]}  | ${result.halted[0]}      | []`);

  for (let step = 0; step < MAX_STEPS; step++) {
    const instruction = instructionName(program.instr, step).padEnd(18, " ");
    const sp = result.sp[step + 1];
    const halted = result.halted[step + 1];
    const stack = formatStack(result.stack[step], sp);
    console.log(`${String(step + 1).padEnd(4, " ")} | ${instruction} | ${sp.padEnd(2, " ")} | ${halted.padEnd(6, " ")} | ${stack}`);
  }
}

async function main() {
  const files = process.argv.slice(2);
  if (files.length < 1 || files.length > 2) {
    usage();
    process.exit(1);
  }

  const programs = files.map(loadProgram);
  const circuits = {
    hash: await wasmTester(path.join(CIRCUITS_DIR, "program_hash.circom")),
    production: await wasmTester(path.join(CIRCUITS_DIR, "zkvm.circom")),
    receipt: await wasmTester(path.join(CIRCUITS_DIR, "receipt_hash.circom")),
    trace: await wasmTester(path.join(CIRCUITS_DIR, "zkvm_trace.circom")),
  };

  const results = [];
  for (const program of programs) {
    const result = await runProgram(program, circuits);
    printProgramRun(program, result);
    results.push(result);
  }

  if (results.length === 2) {
    const aggregateCircuit = await wasmTester(path.join(CIRCUITS_DIR, "receipt_aggregate.circom"));
    const aggregateHash = await aggregateReceipts(aggregateCircuit, results.map((result) => result.receiptHash));
    console.log(`\naggregateHash: ${aggregateHash}`);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
