pragma circom 2.1.6;

include "./zkvm_core.circom";

template ZKVMTrace(n) {
    signal input instr[2 * n];

    signal output out;
    signal output computedProgramHash;
    signal output finalSp;
    signal output sp[n + 1];
    signal output halted[n + 1];
    signal output stack[n][n];

    component core = ZKVMCore(n);

    for (var i = 0; i < 2 * n; i++) {
        core.instr[i] <== instr[i];
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

component main = ZKVMTrace(6);
