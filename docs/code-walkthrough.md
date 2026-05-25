# Code Walkthrough

这份文档按代码路径带你读一遍项目。它不是替代 [mini-zkvm-book.md](mini-zkvm-book.md)，而是把概念落到具体文件和信号上。

## 1. 从入口开始

主要入口有两个：

- [../circuits/zkvm.circom](../circuits/zkvm.circom)：production circuit。
- [../circuits/zkvm_trace.circom](../circuits/zkvm_trace.circom)：trace circuit。

两者都实例化同一个核心组件：

```text
ZKVMCore(10, 4, 4)
```

参数含义：

- `10`：最多 10 条指令。
- `4`：4 个私有输入槽位。
- `4`：4 个公开输入槽位。

production circuit 只公开最终 claim：

- `programHash`
- `publicInputs`
- `out`
- `receiptHash`

trace circuit 用来教学和测试，会暴露：

- `computedProgramHash`
- `computedReceiptHash`
- `finalSp`
- `sp`
- `halted`
- `stack`

## 2. `zkvm_core.circom`: VM 的状态机

[../circuits/zkvm_core.circom](../circuits/zkvm_core.circom) 是最重要的文件。

它的输入：

```text
instr[20]
privateInputs[4]
publicInputs[4]
```

它的输出：

```text
out
programHash
finalSp
sp[11]
halted[11]
stack[10][10]
```

内部状态是：

```text
state[step][column]
```

`state` 是真实栈状态，`stack` 是给 trace circuit 暴露的输出副本。第 `step` 行执行完后，会把 `state[step + 1]` 复制到 `stack[step]`。

## 3. `ProgramHash`: 程序身份

`ProgramHash(n)` 做链式 Poseidon：

```text
state_0 = VM_VERSION
state_{i+1} = Poseidon(state_i, instr_i)
programHash = state_{2n}
```

当前 `VM_VERSION = 2`。版本号进入 hash 是为了给 ISA 和语义升级做域分离。production wrapper 会约束：

```text
core.programHash === programHash
```

所以 prover 不能在同一个公开 program hash 下偷换私有程序。

## 4. `OpcodeLookup`: 固定 opcode 表

[../circuits/opcode_lookup.circom](../circuits/opcode_lookup.circom) 集中处理 opcode 解码。

它接收：

```text
opcode
```

输出两类 flags。

第一类是具体 opcode：

```text
isNop
isPush
isAdd
isMul
isReturn
isReadPrivate
isReadPublic
isAssertEq
isPoseidon2
```

第二类是语义分组：

```text
isPushLike
isPopOne
isPopTwo
usesImmediate
usesPrivateInput
usesPublicInput
usesPoseidon
assertsEqual
returns
```

它用 one-hot 方式约束 opcode 必须恰好匹配一行：

```text
isNop + isPush + ... + isPoseidon2 === 1
```

这不是 PLONK lookup argument，而是 R1CS 里直接可实现的固定表查询。它的价值是把 opcode 解码从 VM transition 中抽出来，后续加指令时更清晰。

## 5. active flags 和 halted

`halted[0] = 0`，每一步都有：

```text
active = 1 - halted[step]
```

具体指令会变成 effective flags：

```text
effectivePush = active * isPush
effectiveReturn = active * isReturn
```

这样 `RETURN` 后的指令不会再改变状态。

但电路还额外要求：

```text
halted[step] * (1 - isNop) === 0
```

所以 halt 后只能出现 `NOP` padding。

## 6. 栈上下界

栈容量是 `n = 10`。电路检查三类边界：

- pop 类指令需要 `sp >= 2`。
- push 类指令需要 `sp < n`。
- `RETURN` 需要 `sp > 0`。

这几条约束防止 prover 伪造普通 VM 不可能产生的 trace。

## 7. 读取栈顶和次栈顶

电路不能动态索引数组，所以它用 selector 取值。

对于每个 `column`：

```text
eqTopColumn = (column == sp - 1)
eqSecondColumn = (column == sp - 2)
```

然后累加：

```text
topValue = sum(eqTopColumn[column] * state[step][column])
secondValue = sum(eqSecondColumn[column] * state[step][column])
```

只有一个 selector 会是 `1`，所以它选出了栈顶和次栈顶。

## 8. 读取私有输入和公开输入

`READ_PRIVATE i` 和 `READ_PUBLIC i` 也使用 selector。

私有输入读取：

```text
privateArgEq[index] = (arg == index)
privateInputValue = sum(privateArgEq[index] * privateInputs[index])
privateInputCount = sum(privateArgEq[index])
```

然后约束：

```text
effectiveReadPrivate * (privateInputCount - 1) === 0
```

如果正在执行 `READ_PRIVATE`，必须恰好匹配一个合法输入槽位。公开输入读取同理。

## 9. 执行算术和 Poseidon

`ADD`、`MUL`、`POSEIDON2` 都消费两个值并写回一个值。

电路先计算候选结果：

```text
sumValue = secondValue + topValue
mulValue = secondValue * topValue
poseidon2.out = Poseidon(secondValue, topValue)
```

然后用 effective flags 选择真正生效的结果：

```text
popOneResultValue = effectiveAdd * sumValue
                  + effectiveMul * mulValue
                  + effectivePoseidon2 * poseidon2.out
```

在代码里这被拆成多个中间 signal，是为了避免非二次约束。

## 10. `ASSERT_EQ`

`ASSERT_EQ` 消费两个值，不写回结果。

核心约束：

```text
effectiveAssertEq * (secondValue - topValue) === 0
```

如果当前指令是 `ASSERT_EQ`，两个值必须相等。如果不是，这条约束不会限制它们。

## 11. 写回下一行状态

每个栈槽位的新值由三部分组成：

```text
state[step + 1][column] = copiedValue + pushedValue + popOneResultCell
```

含义：

- `copiedValue`：保留旧栈中仍然有效的槽位。
- `pushedValue`：push 类指令写入 `sp` 位置。
- `popOneResultCell`：`ADD` / `MUL` / `POSEIDON2` 写回 `sp - 2` 位置。

`ASSERT_EQ` 通过 `isPopTwo` 让 `sp` 减 2，并且不写回结果。

## 12. `RETURN` 和 `out`

`RETURN` 不改变栈，只设置 halt，并把栈底作为输出：

```text
returnedValue = effectiveReturn * state[step][0]
returnAcc[step + 1] = returnAcc[step] + returnedValue
out = returnAcc[n]
```

因为最终要求 `halted[n] === 1`，并且 halt 后只能 `NOP`，有效 `RETURN` 只能出现一次。

## 13. Receipt 和 aggregation

[../circuits/receipt.circom](../circuits/receipt.circom) 有两个模板。

`ReceiptHash`：

```text
receiptHash = PoseidonChain(3001, programHash, publicInputs..., out)
```

`ReceiptAggregator`：

```text
aggregateHash = PoseidonChain(4001, receiptHash_0, receiptHash_1, ...)
```

`3001` 和 `4001` 是 domain separation 常量。它们避免单次 receipt 和聚合 digest 共用同一个哈希域。

## 14. Helper circuits

项目有几个 helper circuit：

- [../circuits/program_hash.circom](../circuits/program_hash.circom)：只计算 `programHash`。
- [../circuits/opcode_table.circom](../circuits/opcode_table.circom)：暴露 opcode lookup flags，方便测试。
- [../circuits/receipt_hash.circom](../circuits/receipt_hash.circom)：只计算 `receiptHash`。
- [../circuits/receipt_aggregate.circom](../circuits/receipt_aggregate.circom)：聚合两个 receipt hash。

这些 helper 不一定是生产系统需要的接口，但它们让教学和测试更清晰。

## 15. JavaScript 层

[../src/assembler.js](../src/assembler.js) 把 `.asm` 文本转成 20 个 instruction cells。

[../src/vm.js](../src/vm.js) 是普通 JS reference VM。测试用它生成预期 trace，再和 Circom trace 比较。

[../scripts/run-example.js](../scripts/run-example.js) 是示例 runner。它走真实 Circom witness，而不是只跑 JS VM，所以它可以直接处理 `POSEIDON2`，不需要引入 `circomlibjs`。

## 16. 测试怎么读

[../test/zkvm.test.js](../test/zkvm.test.js) 可以按三层读：

第一层，正向执行：

- 乘法程序输出 `36`。
- 私有输入和公开输入加法输出 `12`。
- 私有 Poseidon preimage claim 输出 `1`。
- field arithmetic 输出 `3`。

第二层，辅助结构：

- opcode lookup table 对每个 opcode 输出正确 flags。
- production / trace / receipt helper 的 `receiptHash` 一致。
- 两个 receipt hash 可以聚合成 order-sensitive digest。

第三层，负向测试：

- invalid opcode。
- stack underflow。
- empty return。
- input index out of range。
- failed assertion。
- missing return。
- non-`NOP` after return。
- mismatched program hash。

这些负向测试回答的问题是：prover 能不能构造一张普通 VM 不会产生、但电路会接受的 witness？目前这些核心路径都被覆盖了。
