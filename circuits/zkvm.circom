pragma circom 2.1.6;

include "./zkvm_core.circom";

template ZKVMProduction(n, privateInputsCount, publicInputsCount) {
    signal input instr[2 * n];
    signal input privateInputs[privateInputsCount];
    signal input publicInputs[publicInputsCount];
    signal input programHash;
    signal output out;

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

    core.programHash === programHash;
    out <== core.out;
}

component main { public [programHash, publicInputs] } = ZKVMProduction(10, 4, 4);

