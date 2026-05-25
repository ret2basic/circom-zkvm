pragma circom 2.1.6;

include "./receipt.circom";

template ReceiptAggregateMain(count) {
    signal input receiptHashes[count];
    signal output aggregateHash;

    component aggregator = ReceiptAggregator(count);

    for (var i = 0; i < count; i++) {
        aggregator.receiptHashes[i] <== receiptHashes[i];
    }

    aggregateHash <== aggregator.aggregateHash;
}

component main = ReceiptAggregateMain(2);