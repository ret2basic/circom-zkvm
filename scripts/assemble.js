#!/usr/bin/env node

const fs = require("fs");
const { assemble } = require("../src/assembler");

const [, , filePath, rawMaxSteps] = process.argv;

if (!filePath) {
  console.error("usage: node scripts/assemble.js <program.asm> [maxSteps]");
  process.exit(1);
}

const maxSteps = rawMaxSteps === undefined ? 10 : Number(rawMaxSteps);
if (!Number.isInteger(maxSteps) || maxSteps <= 0) {
  console.error("maxSteps must be a positive integer");
  process.exit(1);
}

const source = fs.readFileSync(filePath, "utf8");
const instr = assemble(source, { maxSteps });
console.log(JSON.stringify({ instr: instr.map((value) => value.toString()) }, null, 2));
