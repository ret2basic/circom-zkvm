const FIELD_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;
const VM_VERSION = 2n;

const OPCODES = Object.freeze({
  NOP: 0,
  PUSH: 1,
  ADD: 2,
  MUL: 3,
  RETURN: 4,
  READ_PRIVATE: 5,
  READ_PUBLIC: 6,
  ASSERT_EQ: 7,
  POSEIDON2: 8,
});

const OPCODE_NAMES = Object.freeze(Object.fromEntries(
  Object.entries(OPCODES).map(([name, opcode]) => [opcode, name]),
));

function toField(value) {
  const normalized = BigInt(value) % FIELD_MODULUS;
  return normalized >= 0n ? normalized : normalized + FIELD_MODULUS;
}

function normalizeInputs(values, expectedLength, name) {
  if (!Array.isArray(values) || values.length !== expectedLength) {
    throw new Error(`${name} must contain ${expectedLength} field elements`);
  }

  return values.map(toField);
}

function requirePoseidon2(options) {
  if (typeof options.poseidon2 !== "function") {
    throw new Error("POSEIDON2 execution requires a poseidon2(left, right) callback");
  }

  return (left, right) => toField(options.poseidon2(toField(left), toField(right)));
}

function execute(instr, options = {}) {
  const maxSteps = options.maxSteps ?? instr.length / 2;
  const privateInputs = normalizeInputs(options.privateInputs ?? [0, 0, 0, 0], 4, "privateInputs");
  const publicInputs = normalizeInputs(options.publicInputs ?? [0, 0, 0, 0], 4, "publicInputs");

  if (!Number.isInteger(maxSteps) || maxSteps <= 0) {
    throw new Error("maxSteps must be a positive integer");
  }

  if (instr.length !== 2 * maxSteps) {
    throw new Error(`expected ${2 * maxSteps} instruction cells`);
  }

  const stack = [];
  const stackTrace = [];
  const spTrace = [0];
  const haltedTrace = [0];
  let halted = false;
  let out;

  for (let pc = 0; pc < maxSteps; pc++) {
    const opcode = Number(instr[2 * pc]);
    const rawArg = instr[2 * pc + 1];

    if (halted) {
      if (opcode !== OPCODES.NOP) {
        throw new Error("post-return padding must be NOP");
      }
    } else {
      switch (opcode) {
        case OPCODES.NOP:
          break;
        case OPCODES.PUSH:
          if (stack.length >= maxSteps) {
            throw new Error("stack overflow");
          }
          stack.push(toField(instr[2 * pc + 1]));
          break;
        case OPCODES.READ_PRIVATE: {
          const privateIndex = Number(rawArg);
          if (!Number.isSafeInteger(privateIndex) || privateIndex < 0) {
            throw new Error(`invalid private input index ${rawArg}`);
          }
          if (privateIndex >= privateInputs.length) {
            throw new Error("private input index out of range");
          }
          if (stack.length >= maxSteps) {
            throw new Error("stack overflow");
          }
          stack.push(privateInputs[privateIndex]);
          break;
        }
        case OPCODES.READ_PUBLIC: {
          const publicIndex = Number(rawArg);
          if (!Number.isSafeInteger(publicIndex) || publicIndex < 0) {
            throw new Error(`invalid public input index ${rawArg}`);
          }
          if (publicIndex >= publicInputs.length) {
            throw new Error("public input index out of range");
          }
          if (stack.length >= maxSteps) {
            throw new Error("stack overflow");
          }
          stack.push(publicInputs[publicIndex]);
          break;
        }
        case OPCODES.ADD: {
          if (stack.length < 2) {
            throw new Error("stack underflow");
          }
          const right = stack.pop();
          const left = stack.pop();
          stack.push(toField(left + right));
          break;
        }
        case OPCODES.MUL: {
          if (stack.length < 2) {
            throw new Error("stack underflow");
          }
          const right = stack.pop();
          const left = stack.pop();
          stack.push(toField(left * right));
          break;
        }
        case OPCODES.POSEIDON2: {
          if (stack.length < 2) {
            throw new Error("stack underflow");
          }
          const poseidon2 = requirePoseidon2(options);
          const right = stack.pop();
          const left = stack.pop();
          stack.push(poseidon2(left, right));
          break;
        }
        case OPCODES.ASSERT_EQ: {
          if (stack.length < 2) {
            throw new Error("stack underflow");
          }
          const right = stack.pop();
          const left = stack.pop();
          if (left !== right) {
            throw new Error("ASSERT_EQ failed");
          }
          break;
        }
        case OPCODES.RETURN:
          if (stack.length < 1) {
            throw new Error("return underflow");
          }
          out = stack[0];
          halted = true;
          break;
        default:
          throw new Error(`invalid opcode ${opcode}`);
      }
    }

    spTrace.push(stack.length);
    haltedTrace.push(halted ? 1 : 0);
    stackTrace.push(Array.from({ length: maxSteps }, (_, index) => stack[index] ?? 0n));
  }

  if (!halted) {
    throw new Error("missing RETURN");
  }

  return {
    out,
    finalSp: BigInt(stack.length),
    halted: haltedTrace,
    sp: spTrace,
    stack: stackTrace,
  };
}

function circuitInput(instr, privateInputs, publicInputs, programHash) {
  return {
    instr: instr.map((value) => value.toString()),
    privateInputs: privateInputs.map((value) => value.toString()),
    publicInputs: publicInputs.map((value) => value.toString()),
    programHash: programHash.toString(),
  };
}

module.exports = {
  FIELD_MODULUS,
  OPCODES,
  OPCODE_NAMES,
  VM_VERSION,
  circuitInput,
  execute,
  toField,
};