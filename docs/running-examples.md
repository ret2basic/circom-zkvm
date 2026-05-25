# Running Examples

这份文档带你跑几个完整例子。这里的“跑”不是只执行 JavaScript reference VM，而是用 `circom_tester` 编译并执行真实 Circom witness：production circuit 会检查约束并输出 `out` / `receiptHash`，trace circuit 会输出每一步的 `sp`、`halted` 和 `stack`。

## 1. 准备

先安装依赖：

```bash
npm install
```

你可以先跑完整测试：

```bash
npm test
```

也可以编译所有电路入口：

```bash
npm run compile
npm run compile:trace
npm run compile:hash
npm run compile:opcode-table
npm run compile:receipt
npm run compile:aggregate
```

## 2. 新的 example runner

命令格式：

```bash
npm run example -- <program.asm|program.json> [second-program.asm|json]
```

runner 会做这些事：

1. 读取 `.asm` 或 `.json` 程序。
2. 如果是 `.asm`，用 [../src/assembler.js](../src/assembler.js) 编译成 20 个 instruction cells。
3. 用 [../circuits/program_hash.circom](../circuits/program_hash.circom) 计算 `programHash`。
4. 用 [../circuits/zkvm.circom](../circuits/zkvm.circom) 运行 production witness，并检查约束。
5. 用 [../circuits/receipt_hash.circom](../circuits/receipt_hash.circom) 独立计算 receipt，确认它和 production 输出一致。
6. 用 [../circuits/zkvm_trace.circom](../circuits/zkvm_trace.circom) 运行 trace witness，并打印每一步状态。
7. 如果一次传入两个程序，再用 [../circuits/receipt_aggregate.circom](../circuits/receipt_aggregate.circom) 聚合两个 receipt hash。

## 3. Example 1: article multiplication

命令：

```bash
npm run example -- examples/article-program.asm
```

程序：

```text
PUSH 3
PUSH 6
PUSH 2
MUL
MUL
RETURN
```

执行过程：

| Step | Instruction | Stack | 说明 |
| ---: | --- | --- | --- |
| 0 | initial | `[]` | 空栈。 |
| 1 | `PUSH 3` | `[3]` | 压入 `3`。 |
| 2 | `PUSH 6` | `[3, 6]` | 压入 `6`。 |
| 3 | `PUSH 2` | `[3, 6, 2]` | 压入 `2`。 |
| 4 | `MUL` | `[3, 12]` | `6 * 2 = 12`。 |
| 5 | `MUL` | `[36]` | `3 * 12 = 36`。 |
| 6 | `RETURN` | `[36]` | `out = 36`。 |
| 7-10 | `NOP` | `[36]` | halt 后 padding。 |

你应该看到：

```text
out: 36
finalSp: 1
```

`programHash` 和 `receiptHash` 是长 field element。它们的具体值会由电路计算出来，用来绑定程序身份和公开执行 claim。

## 4. Example 2: field arithmetic

命令：

```bash
npm run example -- examples/field-arithmetic.asm
```

程序：

```text
PUSH p-1
PUSH 2
ADD
PUSH 3
MUL
RETURN
```

其中 `p` 是 BN254 scalar field modulus。Circom 中所有运算默认在 field 里进行，所以：

```text
(p - 1) + 2 = 1
1 * 3 = 3
```

你应该看到：

```text
out: 3
finalSp: 1
```

这个例子提醒读者：本 VM 不是 32-bit CPU。没有额外 range check 时，加法和乘法是 field arithmetic。

## 5. Example 3: private Poseidon preimage claim

命令：

```bash
npm run example -- examples/private-hash-claim.json
```

这里使用 `.json`，因为这个例子需要指定私有输入和公开输入：

```json
{
  "privateInputs": [1, 2, 0, 0],
  "publicInputs": ["7853200120776062878684798364095072458815029376092732009249414926327459813530", 0, 0, 0]
}
```

程序：

```text
READ_PRIVATE 0
READ_PRIVATE 1
POSEIDON2
READ_PUBLIC 0
ASSERT_EQ
PUSH 1
RETURN
```

执行过程：

| Step | Instruction | Stack | 说明 |
| ---: | --- | --- | --- |
| 0 | initial | `[]` | 空栈。 |
| 1 | `READ_PRIVATE 0` | `[1]` | 读取秘密 `1`。 |
| 2 | `READ_PRIVATE 1` | `[1, 2]` | 读取秘密 `2`。 |
| 3 | `POSEIDON2` | `[h]` | 计算 `h = Poseidon(1, 2)`。 |
| 4 | `READ_PUBLIC 0` | `[h, public_h]` | 读取公开 hash。 |
| 5 | `ASSERT_EQ` | `[]` | 约束 `h == public_h`。 |
| 6 | `PUSH 1` | `[1]` | claim 成立，准备返回 `1`。 |
| 7 | `RETURN` | `[1]` | `out = 1`。 |
| 8-10 | `NOP` | `[1]` | padding。 |

你应该看到：

```text
out: 1
finalSp: 1
```

如果把 `publicInputs[0]` 改成错误的 hash，`ASSERT_EQ` 会让 witness 约束失败，程序不会返回一个“失败输出”，而是无法生成有效证明。

## 6. Example 4: aggregate two receipts

命令：

```bash
npm run example -- examples/article-program.asm examples/private-hash-claim.json
```

runner 会先分别运行两个程序，并得到两个 `receiptHash`。然后它运行 receipt aggregation circuit：

```text
aggregateHash = H(4001, receiptHash_0, receiptHash_1)
```

这个 digest 是顺序敏感的：

```text
H(4001, receiptA, receiptB) != H(4001, receiptB, receiptA)
```

注意：这仍然不是完整 recursive proof verifier。它只是把多个公开执行收据聚合成一个公开 digest。完整递归证明还需要在电路里验证上一层 proof。

## 7. `.asm` 和 `.json` 的区别

`.asm` 只包含程序文本。runner 会默认：

```text
privateInputs = [0, 0, 0, 0]
publicInputs = [0, 0, 0, 0]
```

`.json` 可以同时包含：

```json
{
  "instr": [/* 20 instruction cells */],
  "privateInputs": [/* 4 values */],
  "publicInputs": [/* 4 values */]
}
```

需要私有输入或公开输入的例子，优先使用 `.json`。
