pragma circom 2.1.6;

include "./zkvm_core.circom";

template ZKVMProduction(n) {
    signal input instr[2 * n];
    signal input programHash;
    signal output out;

    component core = ZKVMCore(n);

    for (var i = 0; i < 2 * n; i++) {
        core.instr[i] <== instr[i];
    }

    core.programHash === programHash;
    out <== core.out;
}

component main { public [programHash] } = ZKVMProduction(6);

