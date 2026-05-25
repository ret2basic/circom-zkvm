pragma circom 2.1.6;

include "./opcode_lookup.circom";

template OpcodeTableMain() {
    signal input opcode;
    signal output flags[18];

    component lookup = OpcodeLookup();
    lookup.opcode <== opcode;

    flags[0] <== lookup.isNop;
    flags[1] <== lookup.isPush;
    flags[2] <== lookup.isAdd;
    flags[3] <== lookup.isMul;
    flags[4] <== lookup.isReturn;
    flags[5] <== lookup.isReadPrivate;
    flags[6] <== lookup.isReadPublic;
    flags[7] <== lookup.isAssertEq;
    flags[8] <== lookup.isPoseidon2;
    flags[9] <== lookup.isPushLike;
    flags[10] <== lookup.isPopOne;
    flags[11] <== lookup.isPopTwo;
    flags[12] <== lookup.usesImmediate;
    flags[13] <== lookup.usesPrivateInput;
    flags[14] <== lookup.usesPublicInput;
    flags[15] <== lookup.usesPoseidon;
    flags[16] <== lookup.assertsEqual;
    flags[17] <== lookup.returns;
}

component main = OpcodeTableMain();