pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";

template ReceiptHash(publicInputsCount) {
    assert(publicInputsCount > 0);

    var RECEIPT_VERSION = 3001;

    signal input programHash;
    signal input publicInputs[publicInputsCount];
    signal input out;
    signal output receiptHash;

    signal state[publicInputsCount + 3];
    component hasher[publicInputsCount + 2];

    state[0] <== RECEIPT_VERSION;

    hasher[0] = Poseidon(2);
    hasher[0].inputs[0] <== state[0];
    hasher[0].inputs[1] <== programHash;
    state[1] <== hasher[0].out;

    for (var i = 0; i < publicInputsCount; i++) {
        hasher[i + 1] = Poseidon(2);
        hasher[i + 1].inputs[0] <== state[i + 1];
        hasher[i + 1].inputs[1] <== publicInputs[i];
        state[i + 2] <== hasher[i + 1].out;
    }

    hasher[publicInputsCount + 1] = Poseidon(2);
    hasher[publicInputsCount + 1].inputs[0] <== state[publicInputsCount + 1];
    hasher[publicInputsCount + 1].inputs[1] <== out;
    state[publicInputsCount + 2] <== hasher[publicInputsCount + 1].out;

    receiptHash <== state[publicInputsCount + 2];
}

template ReceiptAggregator(count) {
    assert(count > 0);

    var AGGREGATE_VERSION = 4001;

    signal input receiptHashes[count];
    signal output aggregateHash;

    signal state[count + 1];
    component hasher[count];

    state[0] <== AGGREGATE_VERSION;

    for (var i = 0; i < count; i++) {
        hasher[i] = Poseidon(2);
        hasher[i].inputs[0] <== state[i];
        hasher[i].inputs[1] <== receiptHashes[i];
        state[i + 1] <== hasher[i].out;
    }

    aggregateHash <== state[count];
}
