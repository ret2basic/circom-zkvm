pragma circom 2.1.6;

include "./receipt.circom";

template ReceiptHashMain(publicInputsCount) {
    signal input programHash;
    signal input publicInputs[publicInputsCount];
    signal input out;
    signal output receiptHash;

    component receipt = ReceiptHash(publicInputsCount);
    receipt.programHash <== programHash;
    receipt.out <== out;

    for (var i = 0; i < publicInputsCount; i++) {
        receipt.publicInputs[i] <== publicInputs[i];
    }

    receiptHash <== receipt.receiptHash;
}

component main = ReceiptHashMain(4);
