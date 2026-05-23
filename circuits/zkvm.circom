pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/comparators.circom";

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
    signal input isNop;
    signal input isPush;
    signal input isAdd;
    signal input isMul;
    signal output out;

    isNop * (1 - isNop) === 0;
    isPush * (1 - isPush) === 0;
    isAdd * (1 - isAdd) === 0;
    isMul * (1 - isMul) === 0;
    isNop + isPush + isAdd + isMul === 1;

    component columnBelowSp = LessThan(bits);
    columnBelowSp.in[0] <== column;
    columnBelowSp.in[1] <== sp;

    component columnBelowArithmeticResult = LessThan(bits);
    columnBelowArithmeticResult.in[0] <== column + 2;
    columnBelowArithmeticResult.in[1] <== sp;

    signal copyForNopOrPush;
    signal copyForAddOrMul;
    copyForNopOrPush <== (isNop + isPush) * columnBelowSp.out;
    copyForAddOrMul <== (isAdd + isMul) * columnBelowArithmeticResult.out;

    out <== copyForNopOrPush + copyForAddOrMul;
}

template CopyStack(width, bits) {
    signal input sp;
    signal input isNop;
    signal input isPush;
    signal input isAdd;
    signal input isMul;
    signal output out[width];

    component shouldCopy[width];

    for (var column = 0; column < width; column++) {
        shouldCopy[column] = ShouldCopy(column, bits);
        shouldCopy[column].sp <== sp;
        shouldCopy[column].isNop <== isNop;
        shouldCopy[column].isPush <== isPush;
        shouldCopy[column].isAdd <== isAdd;
        shouldCopy[column].isMul <== isMul;
        out[column] <== shouldCopy[column].out;
    }
}

template ZKVM(n) {
    assert(n > 0);

    var OP_NOP = 0;
    var OP_PUSH = 1;
    var OP_ADD = 2;
    var OP_MUL = 3;
    var bits = ceilLog2(n + 2);
    assert(bits <= 252);

    signal input instr[2 * n];
    signal input steps;

    signal output out;
    signal output sp[n + 1];
    signal output stack[n][n];

    signal state[n + 1][n];

    sp[0] <== 0;
    for (var column = 0; column < n; column++) {
        state[0][column] <== 0;
    }

    component opIsNop[n];
    component opIsPush[n];
    component opIsAdd[n];
    component opIsMul[n];
    component stackDepthLtTwo[n];
    component stackIsFull[n];
    component copyStack[n];
    component eqSp[n][n];
    component eqResultColumn[n][n];
    component stepEq[n];

    signal isNop[n];
    signal isPush[n];
    signal isAdd[n];
    signal isMul[n];
    signal isArithmetic[n];
    signal copiedValue[n][n];
    signal pushColumn[n][n];
    signal pushedValue[n][n];
    signal resultColumnForAdd[n][n];
    signal resultColumnForMul[n][n];
    signal sumCandidate[n][n];
    signal mulCandidate[n][n];
    signal addValue[n][n];
    signal mulValue[n][n];
    signal selectedOut[n];
    signal selectedOutAcc[n + 1];
    signal selectedStepAcc[n + 1];

    selectedOutAcc[0] <== 0;
    selectedStepAcc[0] <== 0;

    for (var step = 0; step < n; step++) {
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

        isNop[step] + isPush[step] + isAdd[step] + isMul[step] === 1;
        isArithmetic[step] <== isAdd[step] + isMul[step];

        stackDepthLtTwo[step] = LessThan(bits);
        stackDepthLtTwo[step].in[0] <== sp[step];
        stackDepthLtTwo[step].in[1] <== 2;
        isArithmetic[step] * stackDepthLtTwo[step].out === 0;

        stackIsFull[step] = IsEqual();
        stackIsFull[step].in[0] <== sp[step];
        stackIsFull[step].in[1] <== n;
        isPush[step] * stackIsFull[step].out === 0;

        copyStack[step] = CopyStack(n, bits);
        copyStack[step].sp <== sp[step];
        copyStack[step].isNop <== isNop[step];
        copyStack[step].isPush <== isPush[step];
        copyStack[step].isAdd <== isAdd[step];
        copyStack[step].isMul <== isMul[step];

        for (var column = 0; column < n; column++) {
            eqSp[step][column] = IsEqual();
            eqSp[step][column].in[0] <== column;
            eqSp[step][column].in[1] <== sp[step];

            eqResultColumn[step][column] = IsEqual();
            eqResultColumn[step][column].in[0] <== column;
            eqResultColumn[step][column].in[1] <== sp[step] - 2;

            copiedValue[step][column] <== copyStack[step].out[column] * state[step][column];
            pushColumn[step][column] <== eqSp[step][column].out * isPush[step];
            pushedValue[step][column] <== pushColumn[step][column] * instr[2 * step + 1];

            resultColumnForAdd[step][column] <== eqResultColumn[step][column].out * isAdd[step];
            resultColumnForMul[step][column] <== eqResultColumn[step][column].out * isMul[step];

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

        sp[step + 1] <== sp[step] + isPush[step] - isAdd[step] - isMul[step];

        stepEq[step] = IsEqual();
        stepEq[step].in[0] <== steps;
        stepEq[step].in[1] <== step + 1;
        selectedOut[step] <== stepEq[step].out * stack[step][0];
        selectedOutAcc[step + 1] <== selectedOutAcc[step] + selectedOut[step];
        selectedStepAcc[step + 1] <== selectedStepAcc[step] + stepEq[step].out;
    }

    isAdd[0] + isMul[0] === 0;
    selectedStepAcc[n] === 1;
    out <== selectedOutAcc[n];
}

component main { public [instr, steps] } = ZKVM(5);
