# Mini zkVM Book

这份文档把项目拆成一组很小的概念。读完之后，你应该能回答三个问题：

1. zkVM 到底在证明什么？
2. 为什么需要 execution trace？
3. 为什么一个小小的栈 VM 也已经包含了成熟 zkVM 的核心形状？

这个项目不是 SP1 的复刻版。SP1 可以运行 RISC-V guest program，有完整 prover/verifier 工程和高性能证明系统。这里我们只保留最小骨架，用 Circom 把每一步约束都摊开。

## 1. 普通 VM 和 zkVM 的区别

普通 VM 运行程序，然后告诉你输出。

zkVM 运行程序，然后生成一个证明：

> 我确实按照这个程序运行了，并且输出是这个值。

验证者不需要重新运行程序，也不需要看到所有私有输入。验证者只检查证明。

在本项目里，证明语句可以写成：

> 我知道一段私有程序 `instr`、一组私有输入 `privateInputs`，使得 `instr` 的哈希等于公开的 `programHash`，VM 读取公开的 `publicInputs`，执行到 `RETURN`，并输出公开的 `out`。

这句话里有三个层次：

- `programHash` 绑定程序身份。
- `privateInputs` 是 prover 的秘密 witness。
- `publicInputs` 和 `out` 是 verifier 可以看到的公开数据。

## 2. 程序是数据

在这个 VM 里，每条指令都是两个 field elements：

```text
[opcode, arg]
```

例如：

```text
PUSH 3
PUSH 6
MUL
RETURN
```

会被编码成：

```text
[1, 3, 1, 6, 3, 0, 4, 0, ...NOP padding]
```

`MUL` 和 `RETURN` 不需要参数，但仍然占两个 cell。这样做让电路更简单，因为每一步的 program counter 都固定前进一条指令。

本项目固定 10 条指令，所以 `instr` 有 20 个 cell。短程序后面必须补 `NOP`。

## 3. Trace 是“每一步的状态”

VM 执行程序时，不只产生最终输出，还产生一张执行表。

对于栈 VM，一行 trace 至少包含：

- 当前栈指针 `sp`
- 是否已经 halt
- 每个栈槽位的值

如果程序有 10 步，我们就有 11 个 `sp` 和 `halted` 状态：第 0 个是初始状态，后面每执行一步产生一个新状态。

电路的工作就是约束：

> 第 `i + 1` 行状态必须由第 `i` 行状态和第 `i` 条指令正确计算出来。

这就是 zkVM 的核心。复杂 zkVM 的 trace 更大，有寄存器、内存表、查表参数、系统调用和预编译，但思想仍然是“每一行必须合法过渡到下一行”。

## 4. 栈语义

这个 VM 使用 stack，而不是寄存器。

`PUSH 3`：

```text
[] -> [3]
```

`PUSH 6`：

```text
[3] -> [3, 6]
```

`MUL`：

```text
[3, 6] -> [18]
```

在电路里，这不是普通代码里的 `array.push()` 和 `array.pop()`。我们必须把每个栈槽位的新值都写成约束。

项目里的规则大致是：

- `PUSH` / `READ_PRIVATE` / `READ_PUBLIC` 让 `sp` 加 1。
- `ADD` / `MUL` / `POSEIDON2` 消耗两个值，写回一个值，让 `sp` 减 1。
- `ASSERT_EQ` 消耗两个值，不写回结果，让 `sp` 减 2。
- `NOP` / `RETURN` 不改变栈。

电路还约束了 underflow 和 overflow：空栈不能 `RETURN`，少于两个元素不能 `ADD`，满栈不能继续 push。

## 5. 私有输入和公开输入

真实 zkVM 的用途通常不是证明“我会算 3 * 6”。更有用的问题是：

> 我知道一个秘密，使得它满足某个公开条件。

所以这个项目加入了两类输入：

- `privateInputs[4]`：只给 prover，用作 witness。
- `publicInputs[4]`：作为 public input，verifier 可以看到。

指令：

```text
READ_PRIVATE 0
READ_PUBLIC 0
```

分别把第 0 个私有输入和第 0 个公开输入压入栈。

电路会检查索引范围。`READ_PRIVATE 4` 是非法的，因为只有 `0, 1, 2, 3` 四个槽位。

## 6. ASSERT_EQ 是程序里的约束

很多零知识程序的核心不是输出一个复杂结果，而是证明某个条件成立。

`ASSERT_EQ` 做的事情是：

```text
[a, b] -> []
并约束 a == b
```

如果 witness 让 `a != b`，电路无法生成有效证明。

这很像普通程序里的 `assert(a == b)`，但区别是：在 zkVM 里，这个 assert 会变成证明系统的一部分。

## 7. Poseidon2 是一个小型 precompile

成熟 zkVM 通常会有 precompile 或 syscall，用来高效处理哈希、签名、椭圆曲线等操作。

这个项目只放了一个最小例子：

```text
POSEIDON2
```

它从栈上弹出两个值：

```text
[left, right] -> [Poseidon(left, right)]
```

这让 VM 可以证明一个实际问题：

> 我知道两个秘密值，它们的 Poseidon 哈希等于公开 hash。

程序如下：

```text
READ_PRIVATE 0
READ_PRIVATE 1
POSEIDON2
READ_PUBLIC 0
ASSERT_EQ
PUSH 1
RETURN
```

解释：

1. 读取两个秘密值。
2. 计算 Poseidon 哈希。
3. 读取公开 hash。
4. 断言二者相等。
5. 如果相等，返回 `1`。

这已经是一个有用的零知识程序。它证明“我知道 preimage”，但不泄露 preimage。

## 8. 程序身份：programHash

如果 `instr` 是私有的，验证者怎么知道 prover 没有偷偷换程序？

答案是：公开 `programHash`。

本项目用 Poseidon 链式哈希：

```text
state_0 = VM_VERSION
state_{i+1} = Poseidon(state_i, instr_i)
programHash = state_last
```

电路同时接收私有的 `instr` 和公开的 `programHash`，并约束二者匹配。

这对应成熟 zkVM 里的 program identity。SP1 里 verifier 会绑定 program verification key；这里我们用更简单的 program hash 表达同一个概念。

## 9. RETURN 和 halt

没有 `RETURN` 的 VM 很难表达“程序结束并提交输出”。

这个项目要求：

- 程序必须执行一次 `RETURN`。
- `RETURN` 时栈不能为空。
- `out` 等于栈底元素 `stack[0]`。
- `RETURN` 后只能出现 `NOP` padding。

为什么返回栈底，而不是栈顶？因为这样可以演示一种常见模型：程序可以在栈上保留多个中间值，但选择一个稳定位置作为 public output。这个选择不是唯一的，只是教学上简单。

## 10. Production circuit 和 trace circuit

项目里有两个入口：

- [circuits/zkvm.circom](../circuits/zkvm.circom)：生产入口。
- [circuits/zkvm_trace.circom](../circuits/zkvm_trace.circom)：教学和测试入口。

生产入口公开：

- `programHash`
- `publicInputs`
- `out`

生产入口隐藏：

- `instr`
- `privateInputs`
- `sp`
- `halted`
- `stack`

trace 入口会暴露 `sp`、`halted` 和 `stack`，方便我们检查每一步执行是否符合 reference VM。

这是从教程走向工程的关键一步：调试需要透明，生产需要最小公开面。

## 11. 为什么还不是成熟 zkVM

这个项目故意保持小。它还没有：

- 可变 program counter
- jump 和 branch
- memory table
- 32-bit word 语义
- RISC-V ISA
- guest SDK
- recursive proof
- verifier 合约

但它已经包含了 zkVM 架构里最重要的几个概念：

- 程序被承诺。
- 执行 trace 被约束。
- witness 可以隐藏。
- public input 和 public output 有清晰边界。
- 程序可以通过 assert 表达条件。
- precompile 可以把复杂操作作为 VM 指令。

理解这些之后，再去看 SP1 或 RISC Zero，会少很多黑盒感。

## 12. 推荐阅读顺序

1. 先读 [README.md](../README.md)，知道项目能做什么。
2. 看 [examples/private-hash-claim.asm](../examples/private-hash-claim.asm)，理解一个有用程序。
3. 看 [src/vm.js](../src/vm.js)，用普通 JavaScript 理解 VM 语义。
4. 再看 [circuits/zkvm_core.circom](../circuits/zkvm_core.circom)，把 JS 语义对应到约束。
5. 最后看测试 [test/zkvm.test.js](../test/zkvm.test.js)，学习哪些错误必须被电路拒绝。