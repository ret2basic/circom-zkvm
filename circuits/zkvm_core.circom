pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/comparators.circom";
include "../node_modules/circomlib/circuits/poseidon.circom";

function ceilLog2(value) {
    var bits = 0;
    var capacity = 1;

    while (capacity < value) {
        capacity *= 2;
        bits++;
    }

    return bits;
}

template ShouldCopy(column, bits) {
    signal input sp;
    signal input isSame;
    signal input isPush;
    signal input isAdd;
    signal input isMul;
    signal output out;

    isSame * (1 - isSame) === 0;
    isPush * (1 - isPush) === 0;
    isAdd * (1 - isAdd) === 0;
    isMul * (1 - isMul) === 0;
    isSame + isPush + isAdd + isMul === 1;

    component columnBelowSp = LessThan(bits);
    columnBelowSp.in[0] <== column;
    columnBelowSp.in[1] <== sp;

    component columnBelowArithmeticResult = LessThan(bits);
    columnBelowArithmeticResult.in[0] <== column + 2;
    columnBelowArithmeticResult.in[1] <== sp;

    signal copyForSameOrPush;
    signal copyForAddOrMul;
    copyForSameOrPush <== (isSame + isPush) * columnBelowSp.out;
    copyForAddOrMul <== (isAdd + isMul) * columnBelowArithmeticResult.out;

    out <== copyForSameOrPush + copyForAddOrMul;
}

template CopyStack(width, bits) {
    signal input sp;
    signal input isSame;
    signal input isPush;
    signal input isAdd;
    signal input isMul;
    signal output out[width];

    component shouldCopy[width];

    for (var column = 0; column < width; column++) {
        shouldCopy[column] = ShouldCopy(column, bits);
        shouldCopy[column].sp <== sp;
        shouldCopy[column].isSame <== isSame;
        shouldCopy[column].isPush <== isPush;
        shouldCopy[column].isAdd <== isAdd;
        shouldCopy[column].isMul <== isMul;
        out[column] <== shouldCopy[column].out;
    }
}

template ProgramHash(n) {
    var VM_VERSION = 1;

    signal input instr[2 * n];
    signal output out;

    signal state[2 * n + 1];
    component hasher[2 * n];

    state[0] <== VM_VERSION;
    for (var i = 0; i < 2 * n; i++) {
        hasher[i] = Poseidon(2);
        hasher[i].inputs[0] <== state[i];
        hasher[i].inputs[1] <== instr[i];
        state[i + 1] <== hasher[i].out;
    }

    out <== state[2 * n];
}

template ZKVMCore(n) {
    assert(n > 0);

    var OP_NOP = 0;
    var OP_PUSH = 1;
    var OP_ADD = 2;
    var OP_MUL = 3;
    var OP_RETURN = 4;
    var bits = ceilLog2(n + 2);
    assert(bits <= 252);

    signal input instr[2 * n];

    signal output out;
    signal output programHash;
    signal output finalSp;
    signal output sp[n + 1];
    signal output halted[n + 1];
    signal output stack[n][n];

    signal state[n + 1][n];

    component hash = ProgramHash(n);
    for (var i = 0; i < 2 * n; i++) {
        hash.instr[i] <== instr[i];
    }
    programHash <== hash.out;

    sp[0] <== 0;
    halted[0] <== 0;
    for (var column = 0; column < n; column++) {
        state[0][column] <== 0;
    }

    component opIsNop[n];
    component opIsPush[n];
    component opIsAdd[n];
    component opIsMul[n];
    component opIsReturn[n];
    component stackDepthLtTwo[n];
    component stackIsFull[n];
    component stackIsEmpty[n];
    component copyStack[n];
    component eqSp[n][n];
    component eqResultColumn[n][n];

    signal active[n];
    signal isNop[n];
    signal isPush[n];
    signal isAdd[n];
    signal isMul[n];
    signal isReturn[n];
    signal effectivePush[n];
    signal effectiveAdd[n];
    signal effectiveMul[n];
    signal effectiveReturn[n];
    signal isArithmetic[n];
    signal isSame[n];
    signal copiedValue[n][n];
    signal pushColumn[n][n];
    signal pushedValue[n][n];
    signal resultColumnForAdd[n][n];
    signal resultColumnForMul[n][n];
    signal sumCandidate[n][n];
    signal mulCandidate[n][n];
    signal addValue[n][n];
    signal mulValue[n][n];
    signal returnedValue[n];
    signal returnAcc[n + 1];

    returnAcc[0] <== 0;

    for (var step = 0; step < n; step++) {
        halted[step] * (1 - halted[step]) === 0;
        active[step] <== 1 - halted[step];

        opIsNop[step] = IsEqual();
        opIsNop[step].in[0] <== instr[2 * step];
        opIsNop[step].in[1] <== OP_NOP;
        isNop[step] <== opIsNop[step].out;

        opIsPush[step] = IsEqual();
        opIsPush[step].in[0] <== instr[2 * step];
        opIsPush[step].in[1] <== OP_PUSH;
        isPush[step] <== opIsPush[step].out;

        opIsAdd[step] = IsEqual();
        opIsAdd[step].in[0] <== instr[2 * step];
        opIsAdd[step].in[1] <== OP_ADD;
        isAdd[step] <== opIsAdd[step].out;

        opIsMul[step] = IsEqual();
        opIsMul[step].in[0] <== instr[2 * step];
        opIsMul[step].in[1] <== OP_MUL;
        isMul[step] <== opIsMul[step].out;

        opIsReturn[step] = IsEqual();
        opIsReturn[step].in[0] <== instr[2 * step];
        opIsReturn[step].in[1] <== OP_RETURN;
        isReturn[step] <== opIsReturn[step].out;

        isNop[step] + isPush[step] + isAdd[step] + isMul[step] + isReturn[step] === 1;
        halted[step] * (1 - isNop[step]) === 0;

        effectivePush[step] <== active[step] * isPush[step];
        effectiveAdd[step] <== active[step] * isAdd[step];
        effectiveMul[step] <== active[step] * isMul[step];
        effectiveReturn[step] <== active[step] * isReturn[step];
        isArithmetic[step] <== effectiveAdd[step] + effectiveMul[step];
        isSame[step] <== 1 - effectivePush[step] - effectiveAdd[step] - effectiveMul[step];

        stackDepthLtTwo[step] = LessThan(bits);
        stackDepthLtTwo[step].in[0] <== sp[step];
        stackDepthLtTwo[step].in[1] <== 2;
        isArithmetic[step] * stackDepthLtTwo[step].out === 0;

        stackIsFull[step] = IsEqual();
        stackIsFull[step].in[0] <== sp[step];
        stackIsFull[step].in[1] <== n;
        effectivePush[step] * stackIsFull[step].out === 0;

        stackIsEmpty[step] = IsZero();
        stackIsEmpty[step].in <== sp[step];
        effectiveReturn[step] * stackIsEmpty[step].out === 0;

        copyStack[step] = CopyStack(n, bits);
        copyStack[step].sp <== sp[step];
        copyStack[step].isSame <== isSame[step];
        copyStack[step].isPush <== effectivePush[step];
        copyStack[step].isAdd <== effectiveAdd[step];
        copyStack[step].isMul <== effectiveMul[step];

        for (var column = 0; column < n; column++) {
            eqSp[step][column] = IsEqual();
            eqSp[step][column].in[0] <== column;
            eqSp[step][column].in[1] <== sp[step];

            eqResultColumn[step][column] = IsEqual();
            eqResultColumn[step][column].in[0] <== column;
            eqResultColumn[step][column].in[1] <== sp[step] - 2;

            copiedValue[step][column] <== copyStack[step].out[column] * state[step][column];
            pushColumn[step][column] <== eqSp[step][column].out * effectivePush[step];
            pushedValue[step][column] <== pushColumn[step][column] * instr[2 * step + 1];

            resultColumnForAdd[step][column] <== eqResultColumn[step][column].out * effectiveAdd[step];
            resultColumnForMul[step][column] <== eqResultColumn[step][column].out * effectiveMul[step];

            if (column < n - 1) {
                sumCandidate[step][column] <== state[step][column] + state[step][column + 1];
                mulCandidate[step][column] <== state[step][column] * state[step][column + 1];
            } else {
                sumCandidate[step][column] <== 0;
                mulCandidate[step][column] <== 0;
            }

            addValue[step][column] <== resultColumnForAdd[step][column] * sumCandidate[step][column];
            mulValue[step][column] <== resultColumnForMul[step][column] * mulCandidate[step][column];

            state[step + 1][column] <== copiedValue[step][column] + pushedValue[step][column] + addValue[step][column] + mulValue[step][column];
            stack[step][column] <== state[step + 1][column];
        }

        sp[step + 1] <== sp[step] + effectivePush[step] - effectiveAdd[step] - effectiveMul[step];
        halted[step + 1] <== halted[step] + effectiveReturn[step];
        returnedValue[step] <== effectiveReturn[step] * state[step][0];
        returnAcc[step + 1] <== returnAcc[step] + returnedValue[step];
    }

    halted[n] * (1 - halted[n]) === 0;
    halted[n] === 1;
    finalSp <== sp[n];
    out <== returnAcc[n];
}
