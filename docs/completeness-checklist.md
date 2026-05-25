# Completeness Checklist

这份清单回答一个问题：当前项目在“小而完整的教学 zkVM”这个目标下是否完整。

结论：当前范围内是完整的，可以开始做示例测试和下一轮扩展实验。但它不是完整的生产级 zkVM，也不是完整 recursive proof system。

## 1. 已完成的 VM 功能

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 固定长度程序 | 完成 | 10 条指令，20 个 instruction cells。 |
| 栈 VM | 完成 | 固定 10 个栈槽位，用 `sp` 标记有效长度。 |
| opcode 集合 | 完成 | `NOP`、`PUSH`、`ADD`、`MUL`、`RETURN`、`READ_PRIVATE`、`READ_PUBLIC`、`ASSERT_EQ`、`POSEIDON2`。 |
| opcode lookup table | 完成 | [../circuits/opcode_lookup.circom](../circuits/opcode_lookup.circom) 集中输出 opcode 语义 flags。 |
| 私有输入 | 完成 | `privateInputs[4]`。 |
| 公开输入 | 完成 | `publicInputs[4]`，production public input。 |
| program identity | 完成 | `programHash = PoseidonChain(VM_VERSION, instr...)`。 |
| halt / return | 完成 | 必须 `RETURN`，return 后只能 `NOP`。 |
| public output | 完成 | `out` 来自 return 时的栈底。 |
| receipt hash | 完成 | `receiptHash = H(3001, programHash, publicInputs..., out)`。 |
| receipt aggregation | 完成 | 两个 receipt hash 聚合成 order-sensitive aggregate digest。 |

## 2. 已完成的电路入口

| 电路 | 状态 | npm script |
| --- | --- | --- |
| production VM | 完成 | `npm run compile` |
| trace VM | 完成 | `npm run compile:trace` |
| program hash helper | 完成 | `npm run compile:hash` |
| opcode table helper | 完成 | `npm run compile:opcode-table` |
| receipt hash helper | 完成 | `npm run compile:receipt` |
| receipt aggregate helper | 完成 | `npm run compile:aggregate` |

## 3. 已完成的工具

| 工具 | 状态 | 说明 |
| --- | --- | --- |
| Assembler | 完成 | `npm run assemble -- examples/article-program.asm` |
| Example runner | 完成 | `npm run example -- examples/article-program.asm` |
| JS reference VM | 完成 | 测试 oracle，用于和 Circom trace 对比。 |
| Test suite | 完成 | `npm test` 覆盖正向和负向路径。 |

## 4. 可以直接跑的例子

| 例子 | 命令 | 预期输出 |
| --- | --- | --- |
| 乘法程序 | `npm run example -- examples/article-program.asm` | `out = 36` |
| Field arithmetic | `npm run example -- examples/field-arithmetic.asm` | `out = 3` |
| 私有 Poseidon preimage | `npm run example -- examples/private-hash-claim.json` | `out = 1` |
| Receipt aggregation | `npm run example -- examples/article-program.asm examples/private-hash-claim.json` | 输出 `aggregateHash` |

## 5. 已测试的失败情况

| 失败情况 | 状态 |
| --- | --- |
| invalid opcode | 已测试 |
| stack underflow | 已测试 |
| empty return | 已测试 |
| private/public input index out of range | 已测试 |
| failed `ASSERT_EQ` | 已测试 |
| missing `RETURN` | 已测试 |
| non-`NOP` after `RETURN` | 已测试 |
| mismatched `programHash` | 已测试 |
| opcode lookup flags | 已测试 |
| receipt hash consistency | 已测试 |
| receipt aggregation order sensitivity | 已测试 |

## 6. 当前明确不包含的能力

这些不是 bug，而是当前教学范围之外的能力：

- 没有 jump / branch / dynamic program counter。
- 没有 memory table。
- 没有 32-bit word range check。
- 没有普通 Rust/RISC-V guest program。
- 没有真实 proof generation pipeline，比如 `snarkjs groth16 prove`。
- 没有完整 recursive proof verifier。
- 没有 EVM verifier 或链上验证示例。

## 7. 建议下一轮测试方向

现在可以开始做这些测试：

1. 写更多 `.asm` 程序，确认 assembler 和 trace 输出易读。
2. 手动篡改 `.json` 的 public input，确认 `ASSERT_EQ` 失败。
3. 手动篡改 program hash，确认 production circuit 拒绝。
4. 增加更多 receipt aggregation 组合，确认顺序敏感。
5. 开始设计下一批 opcode，例如 `DUP`、`SWAP`、`SUB`、`EQ`。
