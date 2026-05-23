const { OPCODES } = require("./vm");

const OPCODE_BY_NAME = Object.freeze({
  NOP: OPCODES.NOP,
  PUSH: OPCODES.PUSH,
  ADD: OPCODES.ADD,
  MUL: OPCODES.MUL,
  RETURN: OPCODES.RETURN,
  READ_PRIVATE: OPCODES.READ_PRIVATE,
  READ_PUBLIC: OPCODES.READ_PUBLIC,
  ASSERT_EQ: OPCODES.ASSERT_EQ,
  POSEIDON2: OPCODES.POSEIDON2,
});

const REQUIRES_ARG = new Set(["PUSH", "READ_PRIVATE", "READ_PUBLIC"]);

function stripComment(line) {
  return line.replace(/#.*/, "").replace(/\/\/.*/, "").trim();
}

function parseArg(rawArg, lineNumber, mnemonic) {
  if (rawArg === undefined) {
    if (REQUIRES_ARG.has(mnemonic)) {
      throw new Error(`${mnemonic} requires an argument on line ${lineNumber}`);
    }

    return 0n;
  }

  try {
    return BigInt(rawArg);
  } catch (error) {
    throw new Error(`invalid argument for ${mnemonic} on line ${lineNumber}`);
  }
}

function assemble(source, options = {}) {
  const maxSteps = options.maxSteps ?? 10;
  const instructions = [];

  source.split(/\r?\n/).forEach((line, index) => {
    const cleaned = stripComment(line);
    if (cleaned.length === 0) {
      return;
    }

    const [rawMnemonic, rawArg, extra] = cleaned.split(/\s+/);
    if (extra !== undefined) {
      throw new Error(`too many tokens on line ${index + 1}`);
    }

    const mnemonic = rawMnemonic.toUpperCase();
    const opcode = OPCODE_BY_NAME[mnemonic];
    if (opcode === undefined) {
      throw new Error(`unknown opcode ${rawMnemonic} on line ${index + 1}`);
    }

    if (!REQUIRES_ARG.has(mnemonic) && rawArg !== undefined) {
      throw new Error(`${mnemonic} does not take an argument on line ${index + 1}`);
    }

    instructions.push(opcode, parseArg(rawArg, index + 1, mnemonic));
  });

  if (instructions.length / 2 > maxSteps) {
    throw new Error(`program has more than ${maxSteps} instructions`);
  }

  while (instructions.length / 2 < maxSteps) {
    instructions.push(OPCODES.NOP, 0n);
  }

  return instructions;
}

module.exports = {
  OPCODE_BY_NAME,
  assemble,
};