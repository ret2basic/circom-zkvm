# Mini zkVM Book

这是一份配合本仓库阅读的小书。它的目标不是介绍一个抽象的 zkVM，而是把一个真实可运行的 Circom zkVM 拆开：先看普通 VM 怎么执行，再看同一件事如何变成约束，最后看 production circuit 如何只公开必要信息。

这份文档默认你愿意边读边打开代码。最重要的文件是：

- [../circuits/zkvm_core.circom](../circuits/zkvm_core.circom)：核心约束。
- [../circuits/zkvm.circom](../circuits/zkvm.circom)：生产入口。
- [../circuits/zkvm_trace.circom](../circuits/zkvm_trace.circom)：调试入口。
- [../src/vm.js](../src/vm.js)：普通 JavaScript reference VM。
- [../test/zkvm.test.js](../test/zkvm.test.js)：电路应该接受和拒绝什么。

如果你只记住一句话，可以记这句：

> zkVM 的核心不是“在证明系统里神奇地运行程序”，而是把程序执行的每一步都展开成 trace，然后约束每一行 trace 都是上一行合法执行一条指令得到的结果。

## 0. 这本小书要解决什么问题

很多 zkVM 教程容易从两个极端开始。

一个极端是只讲概念：程序、证明、验证、隐私、public input。读完觉得懂了，但打开电路时发现每个 signal 都很陌生。

另一个极端是直接讲成熟系统：RISC-V、内存一致性、多项式承诺、递归、lookup、precompile。读者还没搞清楚为什么需要 trace，就已经被工程复杂度淹没。

本项目走中间路线：

- VM 小到可以手写。
- 电路真实编译。
- 程序有实际用途。
- production 和 trace 有明确边界。
- 每个失败场景都有测试。

我们先学习一个 10 步、4 个私有输入、4 个公开输入的小栈 VM。它远远不是 SP1 或 RISC Zero，但它已经有 mature zkVM 的关键形状：program identity、private witness、public values、execution trace、halt、assertion、precompile-like hash、固定 lookup table 和递归友好的 receipt commitment。

## 1. 我们到底在证明什么

普通程序运行后给你一个输出。zkVM 还要给你一个证明。

本项目的 production circuit 证明下面这句话：

> 我知道一段私有指令 `instr` 和一组私有输入 `privateInputs`，使得 `instr` 的 Poseidon 链式哈希等于公开的 `programHash`；当这个 VM 读取公开的 `publicInputs` 并执行这段程序时，它会合法 halt，并输出公开的 `out`。

这句话里有四类数据。

| 数据 | 谁知道 | 在哪里出现 | 作用 |
| --- | --- | --- | --- |
| `instr` | prover | private input | 程序本身，长度固定为 20 个 field elements。 |
| `privateInputs` | prover | private input | 私有 witness，比如 secret preimage。 |
| `publicInputs` | prover 和 verifier | public input | 公开条件，比如公开 hash。 |
| `programHash` / `out` | prover 和 verifier | public input / output | 绑定程序身份，并公开程序输出。 |

注意一个细节：这里的 `instr` 是私有的，但 `programHash` 是公开的。验证者不一定看到程序内容，但可以要求证明必须绑定到某个已知 program hash。这是教学版的 program identity。

成熟 zkVM 通常不会让 verifier 直接拿一个普通哈希当程序身份。比如 SP1 会围绕 program verification key 建立证明和验证流程。但思想相同：证明必须绑定到某个确定的程序，不能让 prover 在证明时偷偷换程序。

## 2. Circom 电路和普通代码的差异

普通代码里，你可以写：

```js
stack.push(a + b);
```

这是一条命令。程序执行它，然后内存发生变化。

Circom 里不是这样。Circom 写的是约束：

```text
new_top === a + b
```

约束的意思是：prover 提供的 witness 必须让等式成立。

所以我们在电路里不是“执行程序”，而是“检查一张执行记录是不是合法”。这张执行记录就是 trace。

还有一个很重要的限制：R1CS 约束通常只能是二次的，也就是一条约束里最多有一个乘法形状。下面这种表达式在 Circom 中可能会变成非二次约束：

```text
a * b + c * d + e * f
```

所以 [../circuits/zkvm_core.circom](../circuits/zkvm_core.circom) 会把这类表达式拆开：

```text
immediatePushValue = effectivePush * arg
privatePushValue   = effectiveReadPrivate * privateInputValue
publicPushValue    = effectiveReadPublic * publicInputValue
pushValue          = immediatePushValue + privatePushValue + publicPushValue
```

这不是为了好看，而是为了让电路保持在证明系统能接受的约束形式里。

## 3. Field arithmetic 是默认世界

这个 VM 的所有值都是 BN254 scalar field 里的元素。

这意味着：

```text
p - 1 + 2 = 1
```

其中 `p` 是 field modulus。它不是普通整数里的溢出错误，而是 field 里的正常运算。

测试里有一个例子：

```text
PUSH p-1
PUSH 2
ADD
PUSH 3
MUL
RETURN
```

field 里先得到 `1`，再乘 `3`，最终输出 `3`。

如果你想让 VM 表现得像 32-bit CPU，就必须额外加入 range check 和 wraparound 语义。成熟 zkVM 通常会大量处理这些问题。本项目暂时不做，因为我们先学习 zkVM 的骨架。

## 4. 指令格式：程序是 field elements

本项目的每条指令固定占两个 field elements：

```text
[opcode, arg]
```

比如：

```text
PUSH 3
PUSH 6
MUL
RETURN
```

会被编码成：

```text
[1, 3, 1, 6, 3, 0, 4, 0, ...]
```

`MUL` 不需要参数，但仍然占一个 `arg` cell。这样每一步都知道自己应该读取 `instr[2 * step]` 和 `instr[2 * step + 1]`。

为什么不让不同指令有不同长度？因为电路喜欢固定结构。固定结构意味着：

- 第 `step` 步的 opcode 位置是固定的。
- 第 `step` 步的 arg 位置是固定的。
- trace 长度是固定的。
- 所有循环都能在 compile time 展开。

本项目固定 `n = 10`，所以程序总是 10 条指令，也就是 20 个 instruction cells。短程序后面补 `NOP 0`。

## 5. Opcode 表

当前 VM 有 9 个 opcode。

| Opcode | Value | Stack effect | 说明 |
| --- | ---: | --- | --- |
| `NOP` | `0` | `[] -> []` | padding 或 halt 后空操作。 |
| `PUSH arg` | `1` | `[] -> [arg]` | 把立即数放入栈。 |
| `ADD` | `2` | `[a, b] -> [a + b]` | field 加法。 |
| `MUL` | `3` | `[a, b] -> [a * b]` | field 乘法。 |
| `RETURN` | `4` | 不改变栈 | halt，并把栈底作为 `out`。 |
| `READ_PRIVATE i` | `5` | `[] -> [privateInputs[i]]` | 读取私有输入。 |
| `READ_PUBLIC i` | `6` | `[] -> [publicInputs[i]]` | 读取公开输入。 |
| `ASSERT_EQ` | `7` | `[a, b] -> []` | 约束 `a == b`。 |
| `POSEIDON2` | `8` | `[a, b] -> [Poseidon(a, b)]` | 两输入 Poseidon hash。 |

这里的 stack effect 是局部写法。真实栈上可能还有更早的元素，例如 `[x, a, b] -> [x, a + b]`。

## 6. Assembler 只是为了让程序可读

你可以手写 opcode 数组，但很快就会难读：

```json
{
  "instr": [5, 0, 5, 1, 8, 0, 6, 0, 7, 0, 1, 1, 4, 0, 0, 0, 0, 0, 0, 0]
}
```

所以项目加了一个小 assembler。下面这个程序更像人写的：

```text
READ_PRIVATE 0
READ_PRIVATE 1
POSEIDON2
READ_PUBLIC 0
ASSERT_EQ
PUSH 1
RETURN
```

运行：

```bash
npm run assemble -- examples/private-hash-claim.asm
```

assembler 做的事情很少：解析 opcode、解析参数、检查参数个数、补 `NOP`。它不做 label、不做宏、不做控制流分析。这样设计是故意的，因为现阶段我们要把注意力放在 VM 和电路约束上。

## 7. Trace 是 zkVM 的账本

VM 执行时会产生一串状态。我们把这些状态排成表，就得到 trace。

对于这个栈 VM，一个状态包括：

- `sp`：stack pointer，表示当前栈里有几个有效元素。
- `halted`：程序是否已经 return。
- `stack`：固定长度为 `n` 的栈槽位。

初始状态：

```text
sp = 0
halted = 0
stack = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
```

执行一条指令后，会产生下一行状态。电路检查每一对相邻状态：

```text
(state_i, instr_i) -> state_{i+1}
```

如果任何一行过渡不合法，证明就无法生成。

这个“逐行过渡”是 zkVM 的核心。寄存器 VM、RISC-V VM、WASM VM 也是同样思想，只是 state 更复杂，transition rules 更多。

## 8. 手动跑一个乘法程序

先看一个普通程序：

```text
PUSH 3
PUSH 6
PUSH 2
MUL
MUL
RETURN
```

它计算 `3 * (6 * 2)`。

trace 可以手动写成：

| Step | Instruction | Stack after step | `sp` | `halted` |
| ---: | --- | --- | ---: | ---: |
| 0 | initial | `[]` | 0 | 0 |
| 1 | `PUSH 3` | `[3]` | 1 | 0 |
| 2 | `PUSH 6` | `[3, 6]` | 2 | 0 |
| 3 | `PUSH 2` | `[3, 6, 2]` | 3 | 0 |
| 4 | `MUL` | `[3, 12]` | 2 | 0 |
| 5 | `MUL` | `[36]` | 1 | 0 |
| 6 | `RETURN` | `[36]` | 1 | 1 |
| 7-10 | `NOP` | `[36]` | 1 | 1 |

这个表里的每一行都对应电路中的约束。比如第 4 步 `MUL` 必须证明：

```text
topValue = 2
secondValue = 6
result = 6 * 2 = 12
new stack = [3, 12]
new sp = old sp - 1
```

注意 `RETURN` 不清空栈。它只设置 `halted = 1`，并把 `state[step][0]` 累加进 `out`。

## 9. 为什么 stack 是固定宽度

普通程序可以用动态数组表示栈。但 Circom 电路需要固定数量的 signals。

所以我们把栈写成固定长度：

```text
state[step][0..n-1]
```

`sp` 告诉我们哪些槽位有效。比如：

```text
sp = 3
state = [3, 6, 2, 0, 0, ...]
```

只有前三个值是有效栈元素。后面的值存在于 witness 中，但语义上不属于栈。

电路不能只说“复制有效的那些槽位”，因为“有效”本身也要由约束表达。项目里的 `ShouldCopy` 和 `CopyStack` 就是在做这件事：根据当前操作类型和 `sp`，决定每个列是否应该从上一行复制。

## 10. 一条指令如何选择自己的语义

电路不能写普通的 `switch opcode`。它需要把所有可能分支都表达成约束。

项目中使用 one-hot dispatch：

```text
isNop + isPush + isAdd + isMul + isReturn + isReadPrivate + isReadPublic + isAssertEq + isPoseidon2 === 1
```

这些 flag 现在集中在 [../circuits/opcode_lookup.circom](../circuits/opcode_lookup.circom) 里。它不是 PLONK 那种原生 lookup argument，而是 R1CS/Circom 中能直接表达的固定表查询：opcode 必须恰好匹配表里一行，然后这一行输出 `isPushLike`、`isPopOne`、`usesPoseidon`、`returns` 等语义 flags。

每个 `isX` 仍然来自一个 `IsEqual()` 组件。例如：

```text
isPush = (opcode == OP_PUSH)
```

如果 opcode 是 `PUSH`，那么 `isPush = 1`，其他 opcode flag 都是 `0`。

如果 opcode 是 `99`，所有 flag 都是 `0`，one-hot 总和无法等于 `1`，电路拒绝。

这就是为什么测试里有 “rejects invalid opcodes” 和 “decodes opcodes through the fixed lookup table”。不是 reference VM 拒绝就算完，电路本身也必须拒绝，并且每个合法 opcode 的表输出也要符合预期。

## 11. active 和 halted

`RETURN` 后程序已经结束，但固定 trace 还有剩余行。我们需要一种方式表达：剩下的行只能是 padding。

电路里有：

```text
active = 1 - halted
```

只有 active 时，指令才会产生真实效果。比如：

```text
effectivePush = active * isPush
effectiveReturn = active * isReturn
```

如果已经 halted，`active = 0`，这些 effective flags 都是 `0`。

但仅仅让它们无效还不够。否则 prover 可以在 `RETURN` 后塞任意 opcode，虽然不会改变状态，但程序哈希会变成另一段程序。为了让 padding 规则明确，电路还约束：

```text
halted * (1 - isNop) === 0
```

如果已经 halted，那么 `isNop` 必须是 `1`。所以 `RETURN` 后只能出现 `NOP`。

## 12. 栈上下界：不要相信 prover

如果是普通 interpreter，遇到空栈 `ADD` 会 throw。

在电路里不能依赖 throw。我们要把“不能 underflow”写成约束。

`ADD`、`MUL`、`POSEIDON2` 都需要两个栈元素。电路检查：

```text
sp >= 2
```

Circom 里用 `LessThan(bits)` 表达：

```text
stackDepthLtTwo = sp < 2
(isPopOne + isPopTwo) * stackDepthLtTwo === 0
```

如果当前操作需要 pop，但 `sp < 2`，乘积就是 `1`，约束失败。

`PUSH`、`READ_PRIVATE`、`READ_PUBLIC` 都会让栈增长，所以还要检查：

```text
sp != n
```

`RETURN` 需要至少一个值，所以检查：

```text
sp != 0
```

这些约束看起来琐碎，但它们是安全边界。没有它们，prover 可能构造一张普通 VM 永远不会产生的 trace。

## 13. 读取栈顶和次栈顶

`ADD` 需要读 top 和 second value。普通代码里可以写：

```js
const right = stack.pop();
const left = stack.pop();
```

电路里没有动态索引。我们用等值选择器做一件类似的事。

对于每个 column，检查它是不是 `sp - 1` 或 `sp - 2`：

```text
eqTopColumn[column] = (column == sp - 1)
eqSecondColumn[column] = (column == sp - 2)
```

然后累加：

```text
topValue = sum(eqTopColumn[column] * state[column])
secondValue = sum(eqSecondColumn[column] * state[column])
```

因为只有一个 column 的 selector 是 `1`，其他都是 `0`，最终就选出了目标槽位。

这是一种很常见的电路技巧：用 one-hot selector 实现“动态读取”。

## 14. 写回栈

读值只是第一步。执行完指令后，还要写出下一行状态。

不同指令的写法不同：

- `PUSH` 类指令在 `sp` 位置写新值。
- `ADD` / `MUL` / `POSEIDON2` 在 `sp - 2` 位置写结果。
- `ASSERT_EQ` 不写结果，只弹出两个值。
- `NOP` / `RETURN` 保持状态。

项目把这些情况拆成几个信号：

```text
copiedValue
pushedValue
popOneResultCell
```

最终每个槽位的新值是三者相加：

```text
state[step + 1][column] = copiedValue + pushedValue + popOneResultCell
```

这句话背后的重点是：每个槽位都被约束。prover 不能只把输出值做对，然后随便填写中间栈。

## 15. 私有输入：witness 从哪里进入 VM

零知识程序通常有秘密输入。比如你知道一个 preimage，但不想公开。

本项目有 4 个私有输入槽位：

```text
privateInputs[0..3]
```

`READ_PRIVATE i` 会把 `privateInputs[i]` 压栈。

关键是索引也必须被约束。如果不检查索引，`READ_PRIVATE 999` 的行为就可能变得不明确。电路用 selector 选择输入：

```text
privateArgEq[i] = (arg == i)
privateInputValue = sum(privateArgEq[i] * privateInputs[i])
privateInputCount = sum(privateArgEq[i])
```

然后约束：

```text
effectiveReadPrivate * (privateInputCount - 1) === 0
```

如果当前确实在读私有输入，那么必须恰好匹配一个合法索引。`READ_PRIVATE 4` 会失败，因为没有任何 selector 匹配。

## 16. 公开输入：verifier 看到的条件

公开输入和私有输入的电路结构几乎一样，只是公开性不同。

在 production entrypoint 中：

```text
component main { public [programHash, publicInputs] } = ZKVMProduction(10, 4, 4);
```

这意味着 `programHash` 和 `publicInputs` 是 public input。`out` 是 output，也会公开。

为什么要有 `READ_PUBLIC`？因为程序需要把公开条件放入自己的执行语义里。比如：

```text
READ_PUBLIC 0
ASSERT_EQ
```

这表示“我算出来的值必须等于公开输入 0”。

没有 `READ_PUBLIC`，公开输入就只是电路外面的一组数字，VM 程序无法使用它们。

## 17. ASSERT_EQ：把程序断言变成电路约束

`ASSERT_EQ` 从栈上取两个值，要求它们相等。

栈效果是：

```text
[x, a, b] -> [x]
```

约束是：

```text
effectiveAssertEq * (a - b) === 0
```

如果当前指令不是 `ASSERT_EQ`，`effectiveAssertEq = 0`，这条约束不限制 `a - b`。

如果当前指令是 `ASSERT_EQ`，`effectiveAssertEq = 1`，那么必须有：

```text
a - b = 0
```

这就是为什么失败的 private hash claim 无法通过。程序不是返回了 `0`，而是根本无法满足约束。

## 18. POSEIDON2：一个最小 precompile

成熟 zkVM 会把昂贵或常用操作做成 precompile。比如哈希、签名验证、椭圆曲线运算。

本项目放了一个很小的例子：

```text
POSEIDON2
```

它计算：

```text
Poseidon(2)(secondValue, topValue)
```

然后把结果写回 `sp - 2`。

为什么不用普通 `MUL` 和 `ADD` 组合出哈希？因为哈希电路很复杂，而且 Poseidon 是 ZK 友好的 hash。把它做成一个 VM 指令，可以让 guest program 表达更有用的事情，同时把复杂约束封装在一个组件里。

在测试中，我们用已知向量：

```text
Poseidon(1, 2) = 7853200120776062878684798364095072458815029376092732009249414926327459813530
```

这个值作为公开输入，私有输入是 `[1, 2]`。

## 19. 完整例子：证明我知道 hash preimage

现在看一个真正有用的程序。

私有输入：

```text
privateInputs = [1, 2, 0, 0]
```

公开输入：

```text
publicInputs = [Poseidon(1, 2), 0, 0, 0]
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

手动 trace：

| Step | Instruction | Stack after step | 说明 |
| ---: | --- | --- | --- |
| 0 | initial | `[]` | 空栈。 |
| 1 | `READ_PRIVATE 0` | `[1]` | 读取秘密 `1`。 |
| 2 | `READ_PRIVATE 1` | `[1, 2]` | 读取秘密 `2`。 |
| 3 | `POSEIDON2` | `[h]` | `h = Poseidon(1, 2)`。 |
| 4 | `READ_PUBLIC 0` | `[h, public_h]` | 读取公开 hash。 |
| 5 | `ASSERT_EQ` | `[]` | 约束 `h == public_h`。 |
| 6 | `PUSH 1` | `[1]` | 断言通过后准备返回成功值。 |
| 7 | `RETURN` | `[1]` | `out = 1`。 |
| 8-10 | `NOP` | `[1]` | padding。 |

如果公开输入换成 `123`，第 5 步的 `ASSERT_EQ` 会失败。证明不是输出失败状态，而是无法生成。

这就是很多 ZK 应用的基本形状：隐藏 witness，公开 claim，证明 witness 满足 claim。

## 20. programHash：为什么要绑定程序身份

如果 verifier 只看 `out = 1`，这没有意义。prover 可以写一个程序：

```text
PUSH 1
RETURN
```

它也会输出 `1`，但完全没有证明 preimage。

所以 production circuit 需要公开 `programHash`。本项目的 program hash 是链式 Poseidon：

```text
state_0 = VM_VERSION
state_{i+1} = Poseidon(state_i, instr_i)
programHash = state_{2n}
```

`VM_VERSION = 2`。版本号放进 hash 的初始 state，是为了避免未来改变 ISA 后旧 program hash 和新语义混在一起。

电路做两件事：

1. 根据私有 `instr` 重新计算 `core.programHash`。
2. 在 production wrapper 中约束 `core.programHash === programHash`。

所以 prover 不能在给定公开 program hash 的情况下换程序。

## 21. RETURN：输出从哪里来

`RETURN` 的设计很小，但很关键。

本项目要求：

- 程序最终必须 halt。
- `RETURN` 时栈不能为空。
- `RETURN` 后只能是 `NOP`。
- `out` 来自 `state[step][0]`，也就是返回时的栈底。

为什么用栈底而不是栈顶？

这是一种教学选择。用栈底可以展示“程序可能保留一些状态，但约定某个位置为 public output”。如果以后想更像普通 stack machine，也可以改成返回栈顶。关键不在于选哪一个，而在于电路必须清楚约束输出来自哪里。

`returnAcc` 的作用是把唯一一次有效 `RETURN` 的输出累加出来。因为 `halted[n] === 1` 且 halt 后只能 `NOP`，有效 return 只会发生一次。

## 22. production circuit 和 trace circuit

同一个核心 VM 有两个入口。

production entrypoint：

```text
ZKVMProduction(10, 4, 4)
```

公开：

- `programHash`
- `publicInputs`
- `out`
- `receiptHash`

隐藏：

- `instr`
- `privateInputs`
- `sp`
- `halted`
- `stack`

trace entrypoint：

```text
ZKVMTrace(10, 4, 4)
```

它暴露：

- `computedProgramHash`
- `computedReceiptHash`
- `finalSp`
- 每一步的 `sp`
- 每一步的 `halted`
- 每一步之后的 `stack`

为什么要拆两个入口？因为学习和生产的需求不同。

学习时，我们想看 trace。生产时，我们不想公开 witness trace。成熟系统也有类似分层：debug tooling 可以很透明，最终证明接口必须尽量小。

`receiptHash` 是新增的公开执行收据：

```text
receiptHash = H(programHash, publicInputs, out)
```

它不会验证另一份 proof，所以它还不是完整 recursive proof。但它给递归或聚合层一个稳定的公开承诺：上一层只需要处理一个 compact digest，而不是重新携带整组 public data。

## 23. JavaScript reference VM 的作用

[../src/vm.js](../src/vm.js) 不是证明系统的一部分。它是测试 oracle。

测试会做这件事：

1. 用 assembler 得到 `instr`。
2. 用 JS reference VM 执行，得到预期 `out`、`sp`、`halted`、`stack`。
3. 用 Circom circuit 计算 witness。
4. 比较电路输出和 reference VM 输出。

这样做可以避免我们只测试“电路能不能生成某个 witness”，而是测试“电路语义是不是和 VM 语义一致”。

当然，reference VM 也可能写错。所以测试不是形式化证明，只是工程上非常有价值的交叉检查。

## 24. 程序哈希 helper circuit

测试里没有引入 `circomlibjs` 来计算 Poseidon。原因很实际：少一个 JS 依赖，就少一批供应链和 audit 问题。

项目用 [../circuits/program_hash.circom](../circuits/program_hash.circom) 做 helper circuit。测试先用这个 helper 算出 `programHash`，再喂给 production circuit。

这也有教学价值：program hash 的定义只存在一份 Circom 实现中，不需要维护 JS 版 Poseidon 链式哈希。

## 25. 负面测试比正面测试更重要

一个 zkVM 不能只证明好程序能跑，还必须拒绝坏 trace。

当前测试覆盖了这些失败情况：

| 失败情况 | 为什么必须拒绝 |
| --- | --- |
| invalid opcode | 否则 prover 可以发明未定义语义。 |
| stack underflow | 否则 `ADD` 等指令可以读取不存在的栈值。 |
| empty return | 否则输出来源不明确。 |
| input index out of range | 否则输入读取语义不明确。 |
| failed `ASSERT_EQ` | 否则 claim 不成立也能证明。 |
| missing `RETURN` | 否则程序没有明确输出点。 |
| non-`NOP` after `RETURN` | 否则 padding 规则不清晰。 |
| mismatched `programHash` | 否则 prover 可以换程序。 |
| wrong opcode lookup row | 否则 opcode 语义 flags 可能和 opcode 不一致。 |
| receipt aggregation order ambiguity | 否则多个执行收据的聚合 claim 不够明确。 |

读 zkVM 电路时，一个好习惯是反过来问：我能不能构造一个普通 VM 不会产生、但电路会接受的 witness？负面测试就是这种思路的工程版本。

## 26. 约束安全检查清单

看这个项目的电路时，可以按下面顺序检查。

第一，opcode 是否 one-hot。

```text
每一步必须恰好匹配一个合法 opcode。
```

第二，所有会改变状态的指令是否只在 active 时生效。

```text
effectiveX = active * isX
```

第三，halt 后是否只能 `NOP`。

```text
halted * (1 - isNop) === 0
```

第四，栈读写是否有上下界。

```text
pop needs sp >= 2
push needs sp < n
return needs sp > 0
```

第五，动态索引是否有合法性约束。

```text
READ_PRIVATE / READ_PUBLIC 必须恰好匹配一个输入槽位。
```

第六，public output 是否来自被约束的状态。

```text
out 来自 returnAcc，returnAcc 来自有效 RETURN 时的 state[0]。
```

第七，program identity 是否绑定私有程序。

```text
core.programHash === public programHash
```

第八，公开 receipt 是否绑定公开执行 claim。

```text
receiptHash = H(programHash, publicInputs, out)
```

这些检查不是形式化审计，但足以帮助你发现教学 zkVM 中最常见的漏洞类型。

## 27. 这个项目和 SP1 的对应关系

SP1 是成熟 zkVM，本项目是教学电路。不能把二者混为一谈，但可以建立映射。

| 本项目 | SP1 中的类似概念 | 差异 |
| --- | --- | --- |
| `instr` | guest program / machine code | SP1 运行 RISC-V，本项目运行自定义栈 opcode。 |
| `programHash` | program identity / verifying key 绑定 | 本项目只是 Poseidon hash。 |
| `privateInputs` | private witness / stdin | 本项目固定 4 个 field elements。 |
| `publicInputs` | public values / verifier inputs | 本项目固定 4 个 field elements。 |
| `out` | committed public output | 本项目只有单个 field output。 |
| `receiptHash` | public values digest / recursive claim input | 本项目只做公开 claim hash，不验证上一层 proof。 |
| trace circuit | execution trace / debug tooling | SP1 的 trace 规模和优化复杂得多。 |
| `POSEIDON2` | precompile / syscall | 本项目只有一个 hash 指令。 |
| `ReceiptAggregator` | proof aggregation 的公开数据边界 | 本项目只聚合 receipt digest，不做完整递归 verifier。 |

理解这个映射后，再看 SP1 会更容易：你会知道它不是另一种魔法，而是在同一个基本模型上扩展了 ISA、memory、IO、proof pipeline 和工程工具。

## 28. 这个项目和 RISC Zero 的对应关系

RISC Zero 也证明程序执行，但它围绕 RISC-V guest、image ID、journal 等概念组织。

粗略映射：

| 本项目 | RISC Zero 中的类似概念 |
| --- | --- |
| `programHash` | image ID |
| `out` | journal commit 的公开数据 |
| `privateInputs` | guest 私有输入 |
| execution trace | zkVM 内部执行 trace |

区别仍然很大：RISC Zero 面向真实 guest 程序和完整工具链，本项目面向理解电路如何约束 VM 执行。

## 29. 为什么暂时不做 memory 和 jump

你可能会问：没有 jump、没有 memory，怎么能算 VM？

它当然是一个非常小的 VM。这里暂时不加入 memory 和 jump，是为了控制学习顺序。

加入 jump 需要显式 program counter。现在的第 `step` 步总是执行第 `step` 条指令，所以电路简单。如果加入 `JUMP`，电路需要证明“下一步要读取哪条指令”，这会引入动态选择和控制流约束。

加入 memory 需要读写一致性。你不能只记录 `MSTORE` 和 `MLOAD`，还要证明每次读取拿到的是最近一次写入的值，或者初始默认值。成熟 zkVM 会用 memory table、排序、lookup 等技术处理。

这些都很重要，但应该在理解 trace 和 transition constraint 后再学。

## 30. 如何继续扩展

如果要把这个项目继续往成熟工程推进，一个合理顺序是：

1. 增加 `DUP`、`SWAP`、`SUB`，让栈程序更好写。
2. 增加 `EQ`、`LT`，学习比较约束。
3. 增加显式 `pc`，为 branch 做准备。
4. 加入 `JUMP` / `JUMPI`，学习控制流。
5. 加入 memory table，学习读写一致性。
6. 加入 32-bit word 语义，学习 range check 和 bit decomposition。
7. 接入 `snarkjs`，跑完整 setup / prove / verify。
8. 写 verifier 示例，展示链上或链下验证流程。
9. 在 receipt hash 边界上实验真正的 recursive verifier。

每一步都应该配负面测试。不要只加功能，也要证明坏 witness 被拒绝。

## 附录 A：lookup table 在这个项目里到底是什么

很多现代证明系统说 lookup table，指的是 PLONKish lookup argument：证明某些 witness 值来自一张表，并且这个证明比手写大量约束更便宜。

这个项目使用 Circom/R1CS，所以没有原生 lookup argument。我们实现的是教学版固定表查询：

```text
opcode -> semantic flags
```

表可以理解成：

| opcode | isPushLike | isPopOne | isPopTwo | usesPoseidon | returns |
| ---: | ---: | ---: | ---: | ---: | ---: |
| `0` (`NOP`) | 0 | 0 | 0 | 0 | 0 |
| `1` (`PUSH`) | 1 | 0 | 0 | 0 | 0 |
| `2` (`ADD`) | 0 | 1 | 0 | 0 | 0 |
| `3` (`MUL`) | 0 | 1 | 0 | 0 | 0 |
| `4` (`RETURN`) | 0 | 0 | 0 | 0 | 1 |
| `5` (`READ_PRIVATE`) | 1 | 0 | 0 | 0 | 0 |
| `6` (`READ_PUBLIC`) | 1 | 0 | 0 | 0 | 0 |
| `7` (`ASSERT_EQ`) | 0 | 0 | 1 | 0 | 0 |
| `8` (`POSEIDON2`) | 0 | 1 | 0 | 1 | 0 |

电路做两件事：

1. 证明 opcode 恰好匹配一行。
2. 输出这一行对应的 flags。

这样做的价值不是性能暴涨，而是工程结构更接近成熟 zkVM：opcode 解码集中在一张表里，transition 逻辑只消费表输出的语义 flags。以后增加 `DUP`、`SWAP`、`SUB` 时，我们应该先扩 lookup 表，再扩 transition rules。

## 附录 B：receipt hash 和 recursive proof 的关系

完整 recursive proof 的意思是：一个电路内部验证另一份证明。对于 Groth16/BN254 来说，这通常需要在电路里做 pairing 或非原生域运算，工程量远大于这个教学 zkVM 本身。

所以本项目先实现递归友好的公开承诺层，而不是伪装成已经有完整递归 verifier。

单次执行收据：

```text
receiptHash = PoseidonChain(RECEIPT_VERSION = 3001, programHash, publicInputs..., out)
```

两个收据的聚合 digest：

```text
aggregateHash = PoseidonChain(AGGREGATE_VERSION = 4001, receiptHash_0, receiptHash_1)
```

这提供了一个稳定边界：

- zkVM production circuit 输出 `receiptHash`。
- aggregation circuit 可以把多个 `receiptHash` 合成一个 `aggregateHash`。
- 未来真正的 recursive verifier 可以把“验证上一层 proof 得到的 public claim”压缩成同样的 receipt 格式。

换句话说，现在完成的是 recursive proof 之前必须有的 public data model。还没有完成的是“在 Circom 里验证上一份 Groth16 proof”。这一步可以作为后续独立工程来做。

## 31. 推荐阅读路径

第一遍，不看 Circom，只看 JS：

1. 打开 [../examples/private-hash-claim.asm](../examples/private-hash-claim.asm)。
2. 打开 [../src/assembler.js](../src/assembler.js)。
3. 打开 [../src/vm.js](../src/vm.js)。
4. 手动跑一遍 stack trace。

第二遍，看电路如何表达同一件事：

1. 从 `ProgramHash` 开始。
2. 看 `OpcodeLookup` 如何集中 opcode one-hot 和语义 flags。
3. 看 `READ_PRIVATE` 和 `READ_PUBLIC` 的 selector。
4. 看 `secondValue` 和 `topValue` 如何被选出来。
5. 看 `state[step + 1]` 如何写回。
6. 看 `RETURN` 和 `halted`。
7. 看 `ReceiptHash` 如何绑定公开 claim。

第三遍，看测试：

1. 找到每个 valid case。
2. 找到每个 invalid case。
3. 问自己：如果删掉某条约束，哪个测试会开始通过？

这个问题非常有用。它会迫使你把“约束存在的理由”和“攻击者能构造什么坏 witness”联系起来。

## 32. 小结

这个 mini zkVM 只有 10 步、9 个 opcode、固定 4 个私有输入和 4 个公开输入。它很小，但已经把 zkVM 的核心结构摆在桌面上：

- 程序被编码成 field elements。
- 程序身份由 `programHash` 绑定。
- prover 提供私有 witness。
- verifier 看到 public inputs 和 output。
- execution trace 记录每一步状态。
- 电路约束每一步 transition。
- assertion 把程序条件变成证明条件。
- Poseidon 指令展示了 precompile 的最小形状。
- opcode lookup table 把指令解码集中成一张固定表。
- receipt hash 和 aggregate hash 提供递归友好的公开承诺边界。
- production circuit 隐藏 trace，trace circuit 服务学习和调试。

掌握这些，再进入 SP1、RISC Zero 或更复杂的 zkVM 论文和代码，会更像是在扩展一张熟悉的地图，而不是从黑盒开始猜。