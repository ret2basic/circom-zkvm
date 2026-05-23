pragma circom 2.1.6;

include "./zkvm_core.circom";

template ZKVMTrace(n, privateInputsCount, publicInputsCount) {
    signal input instr[2 * n];
    signal input privateInputs[privateInputsCount];
    signal input publicInputs[publicInputsCount];

    signal output out;
    signal output computedProgramHash;
    signal output finalSp;
    signal output sp[n + 1];
    signal output halted[n + 1];
    signal output stack[n][n];

    component core = ZKVMCore(n, privateInputsCount, publicInputsCount);

    for (var i = 0; i < 2 * n; i++) {
        core.instr[i] <== instr[i];
    }

    for (var privateIndex = 0; privateIndex < privateInputsCount; privateIndex++) {
        core.privateInputs[privateIndex] <== privateInputs[privateIndex];
    }

    for (var publicIndex = 0; publicIndex < publicInputsCount; publicIndex++) {
        core.publicInputs[publicIndex] <== publicInputs[publicIndex];
    }

    out <== core.out;
    computedProgramHash <== core.programHash;
    finalSp <== core.finalSp;

    for (var step = 0; step < n + 1; step++) {
        sp[step] <== core.sp[step];
        halted[step] <== core.halted[step];
    }

    for (var row = 0; row < n; row++) {
        for (var column = 0; column < n; column++) {
            stack[row][column] <== core.stack[row][column];
        }
    }
}

component main = ZKVMTrace(10, 4, 4);
