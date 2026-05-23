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
    signal input isPushLike;
    signal input isPopOne;
    signal input isPopTwo;
    signal output out;

    isSame * (1 - isSame) === 0;
    isPushLike * (1 - isPushLike) === 0;
    isPopOne * (1 - isPopOne) === 0;
    isPopTwo * (1 - isPopTwo) === 0;
    isSame + isPushLike + isPopOne + isPopTwo === 1;

    component columnBelowSp = LessThan(bits);
    columnBelowSp.in[0] <== column;
    columnBelowSp.in[1] <== sp;

    component columnBelowTwoConsumed = LessThan(bits);
    columnBelowTwoConsumed.in[0] <== column + 2;
    columnBelowTwoConsumed.in[1] <== sp;

    signal copyForSameOrPush;
    signal copyForTwoConsumed;
    copyForSameOrPush <== (isSame + isPushLike) * columnBelowSp.out;
    copyForTwoConsumed <== (isPopOne + isPopTwo) * columnBelowTwoConsumed.out;

    out <== copyForSameOrPush + copyForTwoConsumed;
}

template CopyStack(width, bits) {
    signal input sp;
    signal input isSame;
    signal input isPushLike;
    signal input isPopOne;
    signal input isPopTwo;
    signal output out[width];

    component shouldCopy[width];

    for (var column = 0; column < width; column++) {
        shouldCopy[column] = ShouldCopy(column, bits);
        shouldCopy[column].sp <== sp;
        shouldCopy[column].isSame <== isSame;
        shouldCopy[column].isPushLike <== isPushLike;
        shouldCopy[column].isPopOne <== isPopOne;
        shouldCopy[column].isPopTwo <== isPopTwo;
        out[column] <== shouldCopy[column].out;
    }
}

template ProgramHash(n) {
    var VM_VERSION = 2;

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

template ZKVMCore(n, privateInputsCount, publicInputsCount) {
    assert(n > 0);
    assert(privateInputsCount > 0);
    assert(publicInputsCount > 0);

    var OP_NOP = 0;
    var OP_PUSH = 1;
    var OP_ADD = 2;
    var OP_MUL = 3;
    var OP_RETURN = 4;
    var OP_READ_PRIVATE = 5;
    var OP_READ_PUBLIC = 6;
    var OP_ASSERT_EQ = 7;
    var OP_POSEIDON2 = 8;
    var bits = ceilLog2(n + 2);
    assert(bits <= 252);

    signal input instr[2 * n];
    signal input privateInputs[privateInputsCount];
    signal input publicInputs[publicInputsCount];

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
    component opIsReadPrivate[n];
    component opIsReadPublic[n];
    component opIsAssertEq[n];
    component opIsPoseidon2[n];
    component stackDepthLtTwo[n];
    component stackIsFull[n];
    component stackIsEmpty[n];
    component privateArgEq[n][privateInputsCount];
    component publicArgEq[n][publicInputsCount];
    component copyStack[n];
    component eqSp[n][n];
    component eqSecondColumn[n][n];
    component eqTopColumn[n][n];
    component poseidon2[n];

    signal active[n];
    signal isNop[n];
    signal isPush[n];
    signal isAdd[n];
    signal isMul[n];
    signal isReturn[n];
    signal isReadPrivate[n];
    signal isReadPublic[n];
    signal isAssertEq[n];
    signal isPoseidon2[n];
    signal effectivePush[n];
    signal effectiveAdd[n];
    signal effectiveMul[n];
    signal effectiveReturn[n];
    signal effectiveReadPrivate[n];
    signal effectiveReadPublic[n];
    signal effectiveAssertEq[n];
    signal effectivePoseidon2[n];
    signal isPushLike[n];
    signal isPopOne[n];
    signal isPopTwo[n];
    signal isSame[n];
    signal privateInputValue[n];
    signal privateInputCount[n];
    signal privateInputValueAcc[n][privateInputsCount + 1];
    signal privateInputCountAcc[n][privateInputsCount + 1];
    signal publicInputValue[n];
    signal publicInputCount[n];
    signal publicInputValueAcc[n][publicInputsCount + 1];
    signal publicInputCountAcc[n][publicInputsCount + 1];
    signal immediatePushValue[n];
    signal privatePushValue[n];
    signal publicPushValue[n];
    signal pushValue[n];
    signal copiedValue[n][n];
    signal pushedValue[n][n];
    signal secondValue[n];
    signal topValue[n];
    signal secondValueAcc[n][n + 1];
    signal topValueAcc[n][n + 1];
    signal sumValue[n];
    signal mulValue[n];
    signal addResultValue[n];
    signal mulResultValue[n];
    signal poseidon2ResultValue[n];
    signal popOneResultValue[n];
    signal popOneResultCell[n][n];
    signal assertEqDiff[n];
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

        opIsReadPrivate[step] = IsEqual();
        opIsReadPrivate[step].in[0] <== instr[2 * step];
        opIsReadPrivate[step].in[1] <== OP_READ_PRIVATE;
        isReadPrivate[step] <== opIsReadPrivate[step].out;

        opIsReadPublic[step] = IsEqual();
        opIsReadPublic[step].in[0] <== instr[2 * step];
        opIsReadPublic[step].in[1] <== OP_READ_PUBLIC;
        isReadPublic[step] <== opIsReadPublic[step].out;

        opIsAssertEq[step] = IsEqual();
        opIsAssertEq[step].in[0] <== instr[2 * step];
        opIsAssertEq[step].in[1] <== OP_ASSERT_EQ;
        isAssertEq[step] <== opIsAssertEq[step].out;

        opIsPoseidon2[step] = IsEqual();
        opIsPoseidon2[step].in[0] <== instr[2 * step];
        opIsPoseidon2[step].in[1] <== OP_POSEIDON2;
        isPoseidon2[step] <== opIsPoseidon2[step].out;

        isNop[step] + isPush[step] + isAdd[step] + isMul[step] + isReturn[step] + isReadPrivate[step] + isReadPublic[step] + isAssertEq[step] + isPoseidon2[step] === 1;
        halted[step] * (1 - isNop[step]) === 0;

        effectivePush[step] <== active[step] * isPush[step];
        effectiveAdd[step] <== active[step] * isAdd[step];
        effectiveMul[step] <== active[step] * isMul[step];
        effectiveReturn[step] <== active[step] * isReturn[step];
        effectiveReadPrivate[step] <== active[step] * isReadPrivate[step];
        effectiveReadPublic[step] <== active[step] * isReadPublic[step];
        effectiveAssertEq[step] <== active[step] * isAssertEq[step];
        effectivePoseidon2[step] <== active[step] * isPoseidon2[step];
        isPushLike[step] <== effectivePush[step] + effectiveReadPrivate[step] + effectiveReadPublic[step];
        isPopOne[step] <== effectiveAdd[step] + effectiveMul[step] + effectivePoseidon2[step];
        isPopTwo[step] <== effectiveAssertEq[step];
        isSame[step] <== 1 - isPushLike[step] - isPopOne[step] - isPopTwo[step];

        stackDepthLtTwo[step] = LessThan(bits);
        stackDepthLtTwo[step].in[0] <== sp[step];
        stackDepthLtTwo[step].in[1] <== 2;
        (isPopOne[step] + isPopTwo[step]) * stackDepthLtTwo[step].out === 0;

        stackIsFull[step] = IsEqual();
        stackIsFull[step].in[0] <== sp[step];
        stackIsFull[step].in[1] <== n;
        isPushLike[step] * stackIsFull[step].out === 0;

        stackIsEmpty[step] = IsZero();
        stackIsEmpty[step].in <== sp[step];
        effectiveReturn[step] * stackIsEmpty[step].out === 0;

        privateInputValueAcc[step][0] <== 0;
        privateInputCountAcc[step][0] <== 0;
        for (var privateIndex = 0; privateIndex < privateInputsCount; privateIndex++) {
            privateArgEq[step][privateIndex] = IsEqual();
            privateArgEq[step][privateIndex].in[0] <== instr[2 * step + 1];
            privateArgEq[step][privateIndex].in[1] <== privateIndex;
            privateInputValueAcc[step][privateIndex + 1] <== privateInputValueAcc[step][privateIndex] + privateArgEq[step][privateIndex].out * privateInputs[privateIndex];
            privateInputCountAcc[step][privateIndex + 1] <== privateInputCountAcc[step][privateIndex] + privateArgEq[step][privateIndex].out;
        }
        privateInputValue[step] <== privateInputValueAcc[step][privateInputsCount];
        privateInputCount[step] <== privateInputCountAcc[step][privateInputsCount];
        effectiveReadPrivate[step] * (privateInputCount[step] - 1) === 0;

        publicInputValueAcc[step][0] <== 0;
        publicInputCountAcc[step][0] <== 0;
        for (var publicIndex = 0; publicIndex < publicInputsCount; publicIndex++) {
            publicArgEq[step][publicIndex] = IsEqual();
            publicArgEq[step][publicIndex].in[0] <== instr[2 * step + 1];
            publicArgEq[step][publicIndex].in[1] <== publicIndex;
            publicInputValueAcc[step][publicIndex + 1] <== publicInputValueAcc[step][publicIndex] + publicArgEq[step][publicIndex].out * publicInputs[publicIndex];
            publicInputCountAcc[step][publicIndex + 1] <== publicInputCountAcc[step][publicIndex] + publicArgEq[step][publicIndex].out;
        }
        publicInputValue[step] <== publicInputValueAcc[step][publicInputsCount];
        publicInputCount[step] <== publicInputCountAcc[step][publicInputsCount];
        effectiveReadPublic[step] * (publicInputCount[step] - 1) === 0;

        immediatePushValue[step] <== effectivePush[step] * instr[2 * step + 1];
        privatePushValue[step] <== effectiveReadPrivate[step] * privateInputValue[step];
        publicPushValue[step] <== effectiveReadPublic[step] * publicInputValue[step];
        pushValue[step] <== immediatePushValue[step] + privatePushValue[step] + publicPushValue[step];

        secondValueAcc[step][0] <== 0;
        topValueAcc[step][0] <== 0;
        for (var column = 0; column < n; column++) {
            eqSp[step][column] = IsEqual();
            eqSp[step][column].in[0] <== column;
            eqSp[step][column].in[1] <== sp[step];

            eqSecondColumn[step][column] = IsEqual();
            eqSecondColumn[step][column].in[0] <== column;
            eqSecondColumn[step][column].in[1] <== sp[step] - 2;

            eqTopColumn[step][column] = IsEqual();
            eqTopColumn[step][column].in[0] <== column;
            eqTopColumn[step][column].in[1] <== sp[step] - 1;

            secondValueAcc[step][column + 1] <== secondValueAcc[step][column] + eqSecondColumn[step][column].out * state[step][column];
            topValueAcc[step][column + 1] <== topValueAcc[step][column] + eqTopColumn[step][column].out * state[step][column];
        }

        secondValue[step] <== secondValueAcc[step][n];
        topValue[step] <== topValueAcc[step][n];
        sumValue[step] <== secondValue[step] + topValue[step];
        mulValue[step] <== secondValue[step] * topValue[step];

        poseidon2[step] = Poseidon(2);
        poseidon2[step].inputs[0] <== secondValue[step];
        poseidon2[step].inputs[1] <== topValue[step];
        addResultValue[step] <== effectiveAdd[step] * sumValue[step];
        mulResultValue[step] <== effectiveMul[step] * mulValue[step];
        poseidon2ResultValue[step] <== effectivePoseidon2[step] * poseidon2[step].out;
        popOneResultValue[step] <== addResultValue[step] + mulResultValue[step] + poseidon2ResultValue[step];

        assertEqDiff[step] <== secondValue[step] - topValue[step];
        effectiveAssertEq[step] * assertEqDiff[step] === 0;

        copyStack[step] = CopyStack(n, bits);
        copyStack[step].sp <== sp[step];
        copyStack[step].isSame <== isSame[step];
        copyStack[step].isPushLike <== isPushLike[step];
        copyStack[step].isPopOne <== isPopOne[step];
        copyStack[step].isPopTwo <== isPopTwo[step];

        for (var writeColumn = 0; writeColumn < n; writeColumn++) {
            copiedValue[step][writeColumn] <== copyStack[step].out[writeColumn] * state[step][writeColumn];
            pushedValue[step][writeColumn] <== eqSp[step][writeColumn].out * pushValue[step];
            popOneResultCell[step][writeColumn] <== eqSecondColumn[step][writeColumn].out * popOneResultValue[step];
            state[step + 1][writeColumn] <== copiedValue[step][writeColumn] + pushedValue[step][writeColumn] + popOneResultCell[step][writeColumn];
            stack[step][writeColumn] <== state[step + 1][writeColumn];
        }

        sp[step + 1] <== sp[step] + isPushLike[step] - isPopOne[step] - 2 * isPopTwo[step];
        halted[step + 1] <== halted[step] + effectiveReturn[step];
        returnedValue[step] <== effectiveReturn[step] * state[step][0];
        returnAcc[step + 1] <== returnAcc[step] + returnedValue[step];
    }

    halted[n] * (1 - halted[n]) === 0;
    halted[n] === 1;
    finalSp <== sp[n];
    out <== returnAcc[n];
}