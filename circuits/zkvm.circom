pragma circom 2.1.6;

include "./zkvm_core.circom";
include "./receipt.circom";

template ZKVMProduction(n, privateInputsCount, publicInputsCount) {
    signal input instr[2 * n];
    signal input privateInputs[privateInputsCount];
    signal input publicInputs[publicInputsCount];
    signal input programHash;
    signal output out;
    signal output receiptHash;

    component core = ZKVMCore(n, privateInputsCount, publicInputsCount);
    component receipt = ReceiptHash(publicInputsCount);

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

    receipt.programHash <== programHash;
    receipt.out <== core.out;
    for (var receiptPublicIndex = 0; receiptPublicIndex < publicInputsCount; receiptPublicIndex++) {
        receipt.publicInputs[receiptPublicIndex] <== publicInputs[receiptPublicIndex];
    }
    receiptHash <== receipt.receiptHash;
}

component main { public [programHash, publicInputs] } = ZKVMProduction(10, 4, 4);

