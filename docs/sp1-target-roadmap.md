# 从教学 zkVM 走向 SP1 风格工程的计划

这份计划的目标不是把 Circom 项目直接变成 SP1，而是在保留手写电路学习价值的前提下，把当前教学版 zkVM 的工程边界逐步靠近 SP1：明确程序身份、公开输出、私有 witness、固定执行 trace、可调试入口和可生产入口。

## 已完成：建立 SP1 风格的最小工程边界

当前项目已经完成三件事：

1. 引入 program commitment。
   SP1 的 verifier 会绑定某个 program/vkey。我们的 Circom 版本先用 Poseidon 链式哈希约束 `instr`，把 `programHash` 作为 public input。这样 prover 不能在同一个 public program identity 下偷偷换程序。

2. 拆分 debug circuit 和 production circuit。
   教学版输出完整 `sp` 和 `stack` trace，便于测试，但不适合生产。下一版保留 trace 入口用于调试，同时提供 production 入口，只公开最终 `out`。

3. 引入 `RETURN` 和 halt 语义。
   旧版用 `steps` 选择输出，比较像教程动画。成熟 zkVM 更像“程序运行到退出并 commit public values”。我们增加 `RETURN`，要求程序必须返回一次，返回后只能用 `NOP` padding，输出由返回点决定。

此外，项目现在还加入了私有输入、公开输入、`ASSERT_EQ`、`POSEIDON2`、固定 opcode lookup table、receipt hash、receipt aggregation digest 和一个小 assembler。它已经不是单纯的算术 demo，而是一个可以证明“我知道私有 preimage”、并输出递归友好公开收据的最小可用学习 zkVM。

## 下一步：从小型 guest runtime 走向可编程 VM

如果继续往 SP1 的方向靠近，下一阶段可以扩展 ISA 和运行时能力：

1. 增加基本指令：`SUB`、`DUP`、`SWAP`、`EQ`、`LT`。
2. 增加显式 `pc`，为 `JUMP` / `JUMPI` 做准备。
3. 加入 32-bit word 语义：range check、overflow wraparound、bitwise operations。
4. 设计 memory table，加入 `MLOAD` / `MSTORE` 和读写一致性约束。
5. 把当前 assembler 扩展成带 label、常量和错误定位的工具。
6. 增加 proof pipeline，接入 `snarkjs` 的 setup/prove/verify 示例。
7. 在 receipt hash 边界之上实验递归 verifier。当前项目已经能聚合公开 receipt digest，但还没有在 Circom 中验证上一层 Groth16 proof。

## 我们现在和 SP1 的差距

当前项目仍然是教学型 Circom VM，和 SP1 这种成熟 zkVM 的主要差距是：

- SP1 可以运行编译到 RISC-V 的普通 Rust 程序；我们只能运行自定义栈式 opcode。
- SP1 有完整 guest/program/script/prover/verifier 工程模型；我们目前只有 circuit、assembler、reference VM 和测试。
- SP1 通过 program/vkey 绑定程序身份；我们目前用 `programHash` 做教学版 program identity。
- SP1 有 public values 模型；我们目前用 `out` 和 `receiptHash` 表示 public output。
- SP1 有内存、控制流、系统调用、递归和生产 prover 生态；我们目前有递归友好的 receipt/aggregation 边界，但没有完整递归 proof verifier。
- SP1 有性能基准、云端 prover、EVM verifier 模板和安全审计；我们目前只做本地 witness 测试和基础 npm audit。

## 我们需要怎么改进

短期目标是让项目拥有成熟 zkVM 的“形状”：

- `programHash` 对应 SP1 的 program identity。
- `out` 对应 SP1 guest commit 的 public values。
- `receiptHash` 对应一个可聚合的公开执行收据。
- production circuit 默认隐藏 witness trace。
- trace circuit 用于测试、调试和教学。
- `RETURN` 对应 guest 程序退出。
- 固定长度 trace 后半段使用 `NOP` padding。
- opcode lookup table 把 opcode 合法性和语义 flags 集中到一个固定表里。

中期目标是让 VM 变得能写小程序：

- 用 assembler 消除手写 opcode 数组。
- 用更丰富的 ISA 支持条件判断和状态更新。
- 用显式 `pc` 支持控制流。
- 用 memory table 支持更复杂的数据结构。

长期目标是判断是否继续手写 Circom，还是把同一套 VM 迁移到真正的 SP1 guest program。我的建议是：Circom 版本用于理解 zkVM 约束，SP1 版本用于学习成熟工程和生产化 proving。
