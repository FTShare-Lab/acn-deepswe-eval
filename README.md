# ACN on DeepSWE：Coding Harness 与 Claim 复用评测

[方法学](docs/methodology.md) · [评测 Runner 与复跑](docs/runner.md) · [English (runner)](README_EN.md)

[Agent Claim Network（ACN）](https://github.com/FTShare-Lab/agent-claim-network) 在
[DeepSWE v1.1](https://deepswe.datacurve.ai/) 上的评测报告。DeepSWE 是 Datacurve 维护的软件工程
基准：113 道从活跃开源仓库新写的长程任务，每题由手写 verifier 判定 patch 是否通过。本报告回答两个
问题：

1. **Harness**：ACN 作为 coding agent，在 DeepSWE 上能不能稳定解题；
2. **Claim**：一个 agent 解题后沉淀的经验（claim），交给同一道题上的另一个全新 agent，能不能提高
   通过率并降低模型交互成本。

正文只展开已经闭环、且对上述两问有回答的结果；其余对照放在附录。中断、分母不齐或样本过小的诊断
轮次不进入本页。更新日期：2026-09-17。

## 核心结果：r8

r8 是本仓库第 8 轮四臂对照实验。模型为 **DeepSeek-V4.1-Flash**，DeepSWE v1.1 共 **111 题**进入统计，
四臂均有完整用量账本，通过口径为 **Pier 通过**（该题全部测试通过，见[名词速查](#名词速查)）。主对照是
「按需检索 claim 的全新 agent」对「没有 claim 的全新 agent」：

| 指标 | 无 claim 基线 `B_empty` | 按需 claim `B_claim` | 变化 |
| --- | ---: | ---: | ---: |
| Pier 通过 | 63/111（56.76%） | **73/111（65.77%）** | **+10 题（+9.0 pp）** |
| 输入 token | 2,290,656,202 | **1,927,317,486** | **−15.9%** |
| 模型请求 | 13,532 | **12,141** | **−10.3%** |
| 输出 token | 19,728,252 | **19,002,375** | **−3.7%** |

- 按需 claim 是四臂里通过率最高的一臂，比无 claim 多解 10 题，同时输入 token 少 16%、请求少 10%。
- claim 被判定真正用上的 46 题里，通过为 **39/46 对 30/46**。
- 同题配对：claim 独过 20、独挂 10。双侧 exact McNemar p ≈ 0.099，方向一致，尚未跨过 0.05。
- 把同一批 claim 强制塞进上下文（`B_forced_claim`）只多解 2 题。收益来自模型按需取用，不是「多给上下文」。

完整四臂表、成本配对与 claim 命中漏斗见[第 1 节](#1-claim-复用r8)。

## 横向坐标：同一模型上各 harness 的 DeepSWE v1.1 成绩

下表由 DeepSeek 随 [DeepSeek-V4.1-Flash](https://huggingface.co/deepseek-ai/DeepSeek-V4.1-Flash)
发布（2026-09-10）。所有 harness 都使用 V4.1 Flash，每题 8 次采样取 Resolved 率，`temperature=1.0`、
`top_p=0.95`、1M 上下文。DSH 即 DeepSeek Harness，Minimal / Standard / PTC 是它的三种预设，PTC 指
Programmatic Tool Calling。

| Benchmark (Metric) | Claude Code | Codex | OpenCode | Pi | mini-SWE | DSH Minimal | DSH Standard | DSH PTC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| DeepSWE v1.1 (Resolved) | 69.8 | 65.6 | 65.5 | 66.2 | 74.2 | 72.6 | 70.5 | 67.6 |

ACN r8 在同一模型上的位置（Pier 通过，111 题，单次运行）：

| | A（producer） | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 通过率 | 64.86% | 56.76% | **65.77%** | 58.56% |

两张表口径不同：上表是各 harness 单 agent 独立解题、8 次采样的平均值；下表是 ACN 四臂协议下的单次
Pier 通过率。因此只用它建立坐标，不把两者排进同一榜单。可以读出的是：ACN 无 claim 基线落在公开
harness 区间的下沿；加上按需 claim 后，通过率与 Codex、OpenCode、Pi 处于同一区间。

## 名词速查

| 名词 | 含义 |
| --- | --- |
| claim | ACN 里带范围、证据与来源的可检索判断。一个 agent 解题时沉淀，另一个 agent 可通过 router 检索复用 |
| 四臂 | 每道题跑四个彼此隔离的 ACN agent（下称「臂」），除 claim 交付方式外配置完全相同 |
| `A` | producer：先独立解题，并决定是否沉淀 claim |
| `B_empty` | 无 claim 的全新 agent，是所有对照的基线 |
| `B_claim` | 全新 agent，系统上下文只列出 claim 摘要目录，是否调用 router 取正文由模型自己决定（按需） |
| `B_forced_claim` | 全新 agent，框架把同一批 claim 全文直接附在首轮任务上下文里（强制注入） |
| `verified_producer_only` | claim 质量门控：只有通过 verifier 的 producer，其 claim 才会交付给 B 臂；失败 producer 的 claim 被隔离 |
| r8、r4 | 本仓库四臂实验的轮次编号，r8 即第 8 轮 |
| Full-113 | 冻结的全部 113 题；30 题为固定 seed 抽取的 canary 子集 |
| 严格通过 | `verifier_passed=true`：agent 正常完成、verifier 通过、Rust 侧证据齐全 |
| Pier 通过 | `pier_trial.verifier_rewards.reward = 1`：该题全部测试通过。它包含「测试已过但 Rust 证据未齐」的情况，更适合看解题本身；严格通过更适合看正式闭环 |
| Standard | ACN 默认 harness 模式：完整 system prompt 与完整工具面（受管 shell、文件读写与 patch、router 等） |
| Minimal | ACN 内部模式：分步骤工作流提示，读写文件与运行命令都走 shell 工具 `code_run` |
| Concise | ACN 内部模式：只缩短 prompt，工具面与 Standard 相同 |
| Pi-like | ACN 内部模式：精简 prompt，工具面以 `code_run`、`file_read`、`file_write` 为主，并调整分页与上下文压缩。不是外部同名产品的复刻 |
| OpenCode-like | ACN 内部模式：与 Pi-like 类似，局部修改优先使用 `file_patch` |
| Bash-parity | 让 ACN 只通过 shell 读写文件与运行测试，对齐 mini-swe-agent 仅暴露 Bash 的条件，用于与官方 harness 同场对照 |
| MiniSWE | [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent)，DeepSWE 官方榜单使用的 harness |
| injected / used | `injected`：claim 全文确实进入了模型上下文（客观事件）；`used`：模型在收尾自述中报告使用了该 claim |
| F2P / P2P | Fail-to-Pass：修复后应由失败转通过的测试；Pass-to-Pass：修改前后都应通过的测试 |
| exact McNemar p | 同题配对的双侧精确二项检验，只看「一方过、另一方挂」的题 |

## 评测设置

各表共同协议如下，个别偏差在表前单列：

| 项目 | 取值 |
| --- | --- |
| 基准 | DeepSWE v1.1，冻结 113 题候选集 |
| 模型 | r8：DeepSeek-V4.1-Flash。Standard Full-113：记录名 `deepseek-v4-flash-local-exp`。其余轮次以各自冻结 manifest 记录为准 |
| 采样 | `temperature=1.0`，`top_p=0.95`，`reasoning_effort=max` |
| 上下文 | 1,000,000 token |
| 资源 | 每 attempt 2 CPU / 16 GiB 内存 / 20 GiB 存储，20 个 task worker 并行 |
| 运行时 | ACN `acn_eval` 二进制 + Pier 容器评测；模型走 Responses 兼容协议 |
| 分母 | 计划题数固定，失败题不从分母里删除 |

Claim 主结果只读 r8 这一轮。方法学细节见 [docs/methodology.md](docs/methodology.md)，runner 安装与
复跑见 [docs/runner.md](docs/runner.md)。

## 1. Claim 复用（r8）

### 1.1 四臂总表

`verified_producer_only` 四臂对照，111 题，Pier 通过。

| 臂 | Pier 通过 | 输入 token | 输出 token | 模型请求 | 题均请求 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `A` | 72/111（64.86%） | 2,183,995,907 | 18,908,933 | 13,221 | 119.1 |
| `B_empty` | 63/111（56.76%） | 2,290,656,202 | 19,728,252 | 13,532 | 121.9 |
| **`B_claim`** | **73/111（65.77%）** | **1,927,317,486** | **19,002,375** | **12,141** | **109.4** |
| `B_forced_claim` | 65/111（58.56%） | 1,893,296,192 | 18,986,467 | 12,124 | 109.2 |

按需 claim 臂通过 73/111，比基线多 10 题、高 9.0 个百分点，与 producer 臂 `A`（72/111）持平。强制注入
通过 65/111，只比基线多 2 题：收益主要来自模型按需取用，而不是把同一批 claim 一律塞进上下文。

### 1.2 成本：按需 claim 全面更省

`B_claim` 相对 `B_empty`：输入少 3.63 亿 token（−15.9%），请求少 1,391 次（−10.3%），输出少 3.7%。
111 题配对里，78 题输入更低、73 题请求更少；题均请求从 121.9 降到 109.4。

| 配对（`B_claim` − `B_empty`） | 题均差 | 中位差 | claim 更低的题数 | 相对变化 |
| --- | ---: | ---: | ---: | ---: |
| 输入 token | −3,273,322 | −2,372,801 | 78/111 | −15.9% |
| 输出 token | −6,539 | −2,857 | 58/111 | −3.7% |
| reasoning token | −4,432 | −2,245 | 59/111 | −3.2% |
| 模型请求 | −12.5 | −12 | 73/111 | −10.3% |

强制臂的输入和请求同样低于基线，但通过率几乎不涨，所以不把它写成质量优势。

### 1.3 通过率配对

| | `B_claim` 过 | `B_claim` 挂 |
| --- | ---: | ---: |
| `B_empty` 过 | 53 | 10 |
| `B_empty` 挂 | **20** | 28 |

claim 独过 20、独挂 10，双侧 exact McNemar p ≈ 0.099。方向一致，尚未跨过 0.05。它适合作为 r8 的主结论
展示，不写成已经统计显著的全量碾压。

### 1.4 claim 命中漏斗：用上才涨分

`B_claim` 111 题中，claim 实际到达模型的情况：

| 事件 | 题数 | 条数 |
| --- | ---: | ---: |
| bundle 可用 / 检索到 / 注入 | 55/111 | 注入 240 条 |
| 判定 `used` | 46/111 | 用上 169 条 |

按是否真正用上 claim 切开，对照仍是同题 `B_empty`：

| 子集 | n | `B_empty` | `B_claim` | 独过 / 独挂 |
| --- | ---: | ---: | ---: | ---: |
| 注入成功 | 55 | 37/55 | **47/55** | 13 / 3 |
| 判定 `used` | 46 | 30/46 | **39/46** | 11 / 2 |
| `A` 已 Pier 通过 | 72 | 49/72 | **60/72** | 16 / 5 |

`used` 子集上，输入 token 题均约 −290 万（33 题更低），请求题均 −12.1（31 题更少）。复用信号和成本
下降出现在同一批「claim 进入上下文」的题目上，而不是靠把失败经验灌进全量消费者。

### 1.5 质量门控为什么是机制的一部分

另一次已闭环的 Standard Full-113（claim 交付优化版，严格通过；总表见[附录 A.1](#a1-2026-08-30-standard--claim-交付优化--全量)）
按 producer 是否通过 verifier 分层。全量总分没有提升，但 **成功 producer 且产出 claim 的 40 题**上：

| 对照 | `B_empty` | claim 臂 | 差 | 独过 / 独挂 | exact p |
| --- | ---: | ---: | ---: | ---: | ---: |
| `B_claim` | 21/40 | **27/40** | **+15.0 pp** | 11 / 5 | 0.210 |
| `B_forced_claim` | 21/40 | **26/40** | **+12.5 pp** | 11 / 6 | 0.332 |

而 **失败 producer 仍产出 claim 的 68 题**上，按需 / 强制分别为 11/68、12/68，对照 24/68，明显变差。
这支持 ACN 的产品默认：只把 verifier 通过的 producer claim 送进正常检索，失败经验隔离。

### 1.6 跨实验重复出现的正向案例

严格正向定义：同一 run、同一题，`B_empty` 失败、claim 臂严格通过，且 `claim_observation.injected=true`。
下列三题在三次独立 Full-113 里重复出现：

| 题 | 交付方式 | `B_empty` | claim 臂 | 注入记录 | producer 也通过 |
| --- | --- | ---: | ---: | ---: | ---: |
| `arktype-json-schema-refs-dependencies` | 按需 | 0/3 | **3/3** | 3/3 | 3/3 |
| `kcp-go-multiplexed-kcp-streams` | 强制 | 0/3 | **3/3** | 3/3 | 2/3 |
| `prometheus-transactional-reload-status` | 强制 | 0/3 | **3/3** | 3/3 | 2/3 |

被复用的内容是具体工程约束（递归 `$ref` 延迟解析、KCP frame 长度与关闭顺序、事务式 reload 状态机），
不是泛化提示。它们是案例，不是全量成功率。

## 2. Coding Harness

### 2.1 Standard Full-113

闭环实验，四臂各 113 个有效结果。`harness_mode=standard`，模型记录名 `deepseek-v4-flash-local-exp`，
通过口径为严格通过。

| 指标 | `A` | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 严格通过 | **54/113（47.79%）** | **52/113（46.02%）** | 44/113（38.94%） | 50/113（44.25%） |
| 题均整体验收率 | 95.28% | 95.48% | 92.65% | 96.44% |
| 题均 F2P | 87.11% | 88.64% | 83.25% | 87.48% |
| 题均 P2P | 97.99% | 98.71% | 99.80% | 99.76% |
| 模型请求 | 12,427 | 12,479 | 12,516 | 12,231 |
| 输入 token | 1,924,719,428 | 1,888,458,849 | 1,936,412,276 | 1,845,113,368 |

这是目前最干净的「ACN 能解题」数字：`A` 接近一半严格通过，无 claim 基线同量级。这一轮的两个 claim 臂
低于 `B_empty`，本节不把它解释为知识复用收益；claim 主结果以第 1 节的 r8 为准。

### 2.2 与 MiniSWE 同场：Bash-parity

ACN Bash-parity r4 与两次 MiniSWE 运行对照，分母 113，严格通过。

| 运行 | 通过 | 相对 ACN | exact McNemar p |
| --- | ---: | ---: | ---: |
| ACN Bash-parity r4 | **52/113（46.0%）** | — | — |
| MiniSWE attempt 1 | 59/113（52.2%） | −6.2 pp | 0.360 |
| MiniSWE attempt 2 | 54/113（47.8%） | −1.8 pp | 0.868 |

ACN 113 题全部形成有效结果，0 次 Pier / agent 异常、0 个空 patch。相对 MiniSWE attempt 1，ACN 独过 18、
MiniSWE 独过 25；相对 attempt 2 为 17 和 19。差距落在单次波动范围内，不能解释成 ACN runtime 大面积不可用。

ACN 的 61 个失败里，46 个是功能缺口且没有 P2P 回归；44 个失败的 verifier partial ≥ 0.95，12 个只差一个
计分测试。更像「复杂修改能做完、隐藏边界近失」，而不是 runner 或 patch 管道损坏。

### 2.3 Pi-like：通过率持平，交互更省

固定 30 题、四种 ACN 内部 harness 模式、各 3 次重复，共 90 个 A-only 观测；12 个子 run 均闭环。

| Harness | 通过 | 请求 | 输入 token | 相对 Standard |
| --- | ---: | ---: | ---: | --- |
| Standard | 46/90（51.1%） | 10,637 | 1,740,780,205 | 基线 |
| Concise | 40/90（44.4%） | 11,246 | 1,628,488,977 | 请求 +5.7%，输入 −6.5% |
| **Pi-like** | **47/90（52.2%）** | **9,901** | **1,474,897,505** | **请求 −6.9%，输入 −15.3%** |
| OpenCode-like | 39/90（43.3%） | 11,460 | 1,728,781,910 | 请求 +7.7%，输入 −0.7% |

Pi-like 的输出 token 比 Standard 再少 5.4%。只缩短 prompt、保留 Standard 工具面的 Concise 反而请求更多、
通过更少：收益来自工具面与上下文策略，不是「更短系统提示」本身。

| 重复 | Standard 通过 | Pi-like 通过 | Standard 请求 | Pi-like 请求 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 15/30 | 17/30 | 3,456 | 3,318（−4.0%） |
| 2 | 14/30 | 16/30 | 3,699 | 3,265（−11.7%） |
| 3 | 17/30 | 14/30 | 3,482 | 3,318（−4.7%） |
| 合计 | 46/90 | 47/90 | 10,637 | 9,901（−6.9%） |

通过率三次有正有负，合计只多 1 个 task-run，不写成质量碾压；请求下降三次方向一致。30 题是定向 canary，
不是 Full-113 的自然分布。

## 3. 能说什么，不能说什么

可以说：

- ACN Standard 在完整 113 题上接近一半严格通过，并能与 MiniSWE 同场对照。
- r8 四臂中，按需 claim 比无 claim 多过 10 题，输入 token 少 16%，请求少 10%。
- claim 真正用上之后，通过率差距进一步拉开；失败 producer 的 claim 会伤害后续解题，所以质量门控是机制的
  一部分，不是事后补丁。
- Pi-like 在 30 题 × 3 次上保持通过率，并稳定减少请求和输入。

不能说：

- 任意 claim、任意注入方式都能提高通过率。强制臂在 r8 上几乎不涨分。
- Pi-like 已在 Full-113 上取得效率或质量优势。
- McNemar p ≈ 0.099 或成功 producer 40 题的 p = 0.21 已经达到常用显著线。
- ACN 与本页横向坐标里的外部 harness 成绩是同口径可排名的。

## 附录 A. 其他已闭环的 Full-113

### A.1 2026-08-30 Standard · claim 交付优化 · 全量

四臂 113/113 有效。用来说明：**没有质量门控时，全量 claim 不一定高于 `B_empty`。** 第 1.5 节的 +15 pp
来自这次实验的成功 producer 子集，不能代替下表。

| 指标 | `A` | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 严格通过 | 42/113（37.17%） | 47/113（41.59%） | 42/113（37.17%） | 43/113（38.05%） |
| 模型请求 | 13,191 | 13,668 | 13,189 | 12,639 |
| 输入 token | 2,046,128,531 | 2,274,419,883 | 2,191,873,914 | 1,955,384,454 |

### A.2 成功 producer 子集的跨 run 复核

同一分层（`A` 通过且产出 claim）在不同闭环 Full-113 上并不总是正：

| 实验 | 有效配对 | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 08-26 Standard | 54 | 34/54 | 31/54 | 38/54 |
| 08-29 Minimal | 43 | 28/43 | 26/43 | 26/43 |
| 08-30 Standard 优化 | 40 | 21/40 | 27/40 | 26/40 |

08-30 是最强的正向子集；08-26 / 08-29 的同类子集接近或为负。跨 run 不稳定，所以正文以 r8 总表为主，
40 题 +15 pp 只作为质量门控的条件证据。

## 附录 B. 口径说明

- 通过、Pier 通过、Gate 三者分开：Gate 通过只表示实验证据齐全，不等于解题成功。
- 题均 F2P / P2P / partial 是逐题等权平均，不是把全部测试用例池化。
- token 为用量账本观测值；若存在 incomplete model response，总量视为下界。r8 四臂的 `audit_incomplete`
  均为 0。
- 模型请求按账本实计，不是计费，也不是墙钟。
- `injected` 是客观交付事件；`used` 来自收尾自述，需与通过率配对一起读。
- 未收录中断、分母不齐或样本过小的诊断轮次。

## 复现与更多文档

- [docs/runner.md](docs/runner.md)：评测 runner 的安装、任务冻结、启动配置、产物与 Gate
- [docs/methodology.md](docs/methodology.md)：数据集、官方口径、ACN 对齐配置、四臂可见性矩阵与指标定义
- [docs/claim_harness_design.md](docs/claim_harness_design.md)：被评测的 claim harness 变体设计
- [docs/claim_harness_experiment.md](docs/claim_harness_experiment.md)：两个 ACN revision 的配对实验协议
- [docs/automated_run.md](docs/automated_run.md) · [docs/solver_aligned_run.md](docs/solver_aligned_run.md)：自动化与全量运行
- [docs/acn_integration.md](docs/acn_integration.md)：`acn_eval` 构建与 `result.json` / `events.jsonl` 契约
- [CONTRIBUTING.md](CONTRIBUTING.md) · 许可证：MIT OR Apache-2.0（[LICENSE-MIT](LICENSE-MIT)，[LICENSE-APACHE](LICENSE-APACHE)）

## 引用

```bibtex
@misc{acn-deepswe-eval-2026,
  title        = {ACN on DeepSWE: Coding Harness and Claim Reuse},
  author       = {Agent Claim Network},
  year         = {2026},
  howpublished = {https://github.com/FTShare-Lab/acn-deepswe-eval},
  note         = {DeepSWE v1.1 four-arm evaluation}
}
```
