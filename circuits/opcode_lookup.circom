pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/comparators.circom";

template OpcodeLookup() {
    signal input opcode;

    signal output isNop;
    signal output isPush;
    signal output isAdd;
    signal output isMul;
    signal output isReturn;
    signal output isReadPrivate;
    signal output isReadPublic;
    signal output isAssertEq;
    signal output isPoseidon2;
    signal output isPushLike;
    signal output isPopOne;
    signal output isPopTwo;
    signal output usesImmediate;
    signal output usesPrivateInput;
    signal output usesPublicInput;
    signal output usesPoseidon;
    signal output assertsEqual;
    signal output returns;

    component opIs[9];

    for (var row = 0; row < 9; row++) {
        opIs[row] = IsEqual();
        opIs[row].in[0] <== opcode;
        opIs[row].in[1] <== row;
    }

    isNop <== opIs[0].out;
    isPush <== opIs[1].out;
    isAdd <== opIs[2].out;
    isMul <== opIs[3].out;
    isReturn <== opIs[4].out;
    isReadPrivate <== opIs[5].out;
    isReadPublic <== opIs[6].out;
    isAssertEq <== opIs[7].out;
    isPoseidon2 <== opIs[8].out;

    isNop + isPush + isAdd + isMul + isReturn + isReadPrivate + isReadPublic + isAssertEq + isPoseidon2 === 1;

    isPushLike <== isPush + isReadPrivate + isReadPublic;
    isPopOne <== isAdd + isMul + isPoseidon2;
    isPopTwo <== isAssertEq;
    usesImmediate <== isPush;
    usesPrivateInput <== isReadPrivate;
    usesPublicInput <== isReadPublic;
    usesPoseidon <== isPoseidon2;
    assertsEqual <== isAssertEq;
    returns <== isReturn;
}
