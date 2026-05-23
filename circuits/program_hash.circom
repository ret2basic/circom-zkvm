pragma circom 2.1.6;

include "./zkvm_core.circom";

template ProgramHashMain(n) {
    signal input instr[2 * n];
    signal output computedProgramHash;

    component hash = ProgramHash(n);

    for (var i = 0; i < 2 * n; i++) {
        hash.instr[i] <== instr[i];
    }

    computedProgramHash <== hash.out;
}

component main = ProgramHashMain(10);
