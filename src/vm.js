const FIELD_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

const OPCODES = Object.freeze({
  NOP: 0,
  PUSH: 1,
  ADD: 2,
  MUL: 3,
});

function toField(value) {
  const normalized = BigInt(value) % FIELD_MODULUS;
  return normalized >= 0n ? normalized : normalized + FIELD_MODULUS;
}

function execute(instr, steps, maxSteps = instr.length / 2) {
  if (!Number.isInteger(maxSteps) || maxSteps <= 0) {
    throw new Error("maxSteps must be a positive integer");
  }

  if (instr.length !== 2 * maxSteps) {
    throw new Error(`expected ${2 * maxSteps} instruction cells`);
  }

  if (!Number.isInteger(steps) || steps < 1 || steps > maxSteps) {
    throw new Error("steps must be between 1 and maxSteps");
  }

  const stack = [];
  const stackTrace = [];
  const spTrace = [0];

  for (let pc = 0; pc < maxSteps; pc++) {
    const opcode = Number(instr[2 * pc]);
    const arg = toField(instr[2 * pc + 1]);

    switch (opcode) {
      case OPCODES.NOP:
        break;
      case OPCODES.PUSH:
        if (stack.length >= maxSteps) {
          throw new Error("stack overflow");
        }
        stack.push(arg);
        break;
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
      default:
        throw new Error(`invalid opcode ${opcode}`);
    }

    spTrace.push(stack.length);
    stackTrace.push(Array.from({ length: maxSteps }, (_, index) => stack[index] ?? 0n));
  }

  return {
    out: stackTrace[steps - 1][0],
    sp: spTrace,
    stack: stackTrace,
  };
}

function circuitInput(instr, steps) {
  return {
    instr: instr.map((value) => value.toString()),
    steps,
  };
}

module.exports = {
  FIELD_MODULUS,
  OPCODES,
  circuitInput,
  execute,
  toField,
};
