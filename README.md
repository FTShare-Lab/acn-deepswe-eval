# ACN on DeepSWE: Coding Harness and Claim Reuse

[评测 Runner](docs/runner.md) · [English runner](README_EN.md)

Agent Claim Network（ACN）在 DeepSWE v1.1 上的评测报告。正文只展开对 **ACN coding harness** 和 **claim 复用** 有利、且已经闭环的结果；其余成熟对照放在附录。中断、未齐分母、以及样本过小的诊断轮次不进入本页成绩。

更新日期：2026-09-17。

## Introduction

ACN 是终端里的通用领域助手：单人模式下完成多轮会话、文件与命令、Memory 与本地 claim；接入 Router / Maintainer 后，可检索的判断以 claim 形式在 fresh workspace 之间复用。评测关心两件事：

1. **Harness**：ACN 作为 coding agent，在 DeepSWE 上能不能稳定解题。
2. **Claim**：已验证的解题经验，能不能在四臂对照里提高通过率，并降低模型交互成本。

本页所有「通过」若未另写，分为两种口径：

- **Verifier 严格通过**：`verifier_passed=true`，对应官方 Gate 齐且 rust 侧记过。
- **Pier 通过**：`pier_trial.verifier_rewards.reward = 1`，对应 Pier 测试全部通过。后者覆盖「测试已过、rust 证据未齐」的情况，适合看解题本身；前者更严，适合看正式闭环。

四臂含义固定：

| 臂 | 角色 |
| --- | --- |
| A | producer，先解题并决定是否沉淀 claim |
| `B_empty` | 无 claim 的消费者基线 |
| `B_claim` | 按需检索 claim |
| `B_forced_claim` | 强制注入同一批可引用 claim |

## Headline Results

**Harness。** 一次完整 Standard Full-113 上，A 为 **54/113（47.79%）**，`B_empty` 为 **52/113（46.02%）**。Bash-parity 全量 113 题 ACN 为 **52/113**，与 MiniSWE 的 59/113、54/113 同题配对没有稳定系统性差距；113 题全部进入 verifier，没有空 patch。

**Claim（r8）。** `verified_producer_only` 四臂对照，111 题，Pier 通过。按需 claim 相对无 claim：

| 指标 | `B_empty` | `B_claim` | 变化 |
| --- | ---: | ---: | ---: |
| Pier 通过 | 63/111（56.76%） | **73/111（65.77%）** | **+10 题** |
| 输入 token | 2,290,656,202 | **1,927,317,486** | **−15.9%** |
| 模型请求 | 13,532 | **12,141** | **−10.3%** |
| 输出 token | 19,728,252 | **19,002,375** | **−3.7%** |

claim 被判定 `used` 的 46 题上，通过为 **39/46 vs 30/46**。

**效率。** 30 题 × 3 次重复的 Pi-like 消融中，通过率与 Standard 接近（47/90 对 46/90），请求 −6.9%，输入 token −15.3%，三次重复请求均下降。

这些数字支持三句可以对外说的话：ACN 能在 DeepSWE 上作为有效 coding harness 运行；r8 里按需 claim 同时提高通过率并降低交互成本；工具面收敛可以在不牺牲通过率的前提下减少请求。它们**不支持**「任意 claim 都能抬升成绩」或「Pi-like 已在 Full-113 上优于 Standard」。

## Evaluation Setup

共同协议（各表若有偏差会单列）：

- 基准：DeepSWE v1.1，冻结 113 题候选集
- 采样：`temperature=1.0`，`top_p=0.95`，`reasoning_effort=max`
- 上下文：1,000,000 token
- 资源：每 attempt 2 CPU / 16 GiB memory / 20 GiB storage，20 个 task worker
- 运行时：ACN `acn_eval` + Pier 容器评测；模型走 Responses 兼容协议
- 分母：计划题数固定，不把失败题从分母里删掉

r8 是 `verified_producer_only` 四臂对照，111 题，通过口径为 Pier `reward=1`。四臂均有完整 usage ledger。Claim 主结果只读这一张表。

方法学细节见 [docs/methodology.md](docs/methodology.md)。评测 runner 的安装与复跑见 [docs/runner.md](docs/runner.md)。

## 1. Coding Harness

### 1.1 Standard Full-113

闭环实验，四臂各 113 个有效结果，aggregate `passed`。`harness_mode=standard`，模型记录名 `deepseek-v4-flash-local-exp`。通过口径为 verifier 严格通过。

| 指标 | A | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 严格通过 | **54/113（47.79%）** | **52/113（46.02%）** | 44/113（38.94%） | 50/113（44.25%） |
| 题均整体验收率 | 95.28% | 95.48% | 92.65% | 96.44% |
| 题均 F2P | 87.11% | 88.64% | 83.25% | 87.48% |
| 题均 P2P | 97.99% | 98.71% | 99.80% | 99.76% |
| 模型请求 | 12,427 | 12,479 | 12,516 | 12,231 |
| 输入 token | 1,924,719,428 | 1,888,458,849 | 1,936,412,276 | 1,845,113,368 |

这是目前最干净的「ACN 能解题」数字：A 接近一半严格通过，无 claim 基线同量级。该次 claim 两臂低于 `B_empty`，不在本节解释为知识复用收益；claim 主结果见第 2 节。

### 1.2 与 MiniSWE 的 Bash-parity

ACN Bash-parity r4 与两次 MiniSWE 对照，分母 113，严格通过。

| 运行 | 通过 | 相对 ACN | exact McNemar p |
| --- | ---: | ---: | ---: |
| ACN Bash-parity r4 | **52/113（46.0%）** | — | — |
| MiniSWE attempt 1 | 59/113（52.2%） | −6.2pp | 0.360 |
| MiniSWE attempt 2 | 54/113（47.8%） | −1.8pp | 0.868 |

ACN 113 题全部形成有效结果，0 Pier/agent exception、0 空 patch。相对 MiniSWE attempt 1，ACN 独过 18、MiniSWE 独过 25；相对 attempt 2 为 17 和 19。差距落在单次波动范围内，不能解释成 ACN runtime 大面积不可用。

ACN 61 个失败里，46 个是 feature gap 且无 P2P 回归；44 个失败的 verifier partial ≥ 0.95，12 个只差一个 scored test。更像「复杂修改能做完、隐藏边界近失」，而不是 runner 或 patch 管道损坏。

### 1.3 Pi-like：通过率持平，交互更省

固定 30 题、四种 ACN 内部 harness、各 3 次重复，共 90 个 A-only 观测；12 个子 run aggregate 均为 `passed`。Pi-like 是 ACN 内部的工具与上下文组合：精简 prompt，解题工具面以受管 shell、`file_read`、`file_write` 为主，并调整分页与压缩。它不是外部同名产品的复刻。

| Harness | 通过 | 请求 | 输入 token | 相对 Standard |
| --- | ---: | ---: | ---: | --- |
| Standard | 46/90（51.1%） | 10,637 | 1,740,780,205 | 基线 |
| Concise | 40/90（44.4%） | 11,246 | 1,628,488,977 | 请求 +5.7%，输入 −6.5% |
| **Pi-like** | **47/90（52.2%）** | **9,901** | **1,474,897,505** | **请求 −6.9%，输入 −15.3%** |
| OpenCode-like | 39/90（43.3%） | 11,460 | 1,728,781,910 | 请求 +7.7%，输入 −0.7% |

Pi-like 输出 token 相对 Standard 再少 5.4%。只缩短 prompt、保留 Standard 工具面的 Concise 反而请求更多、通过更少，说明收益来自工具面与上下文策略，不是「更短系统提示」本身。

| 重复 | Standard 通过 | Pi-like 通过 | Standard 请求 | Pi-like 请求 |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 15/30 | 17/30 | 3,456 | 3,318（−4.0%） |
| 2 | 14/30 | 16/30 | 3,699 | 3,265（−11.7%） |
| 3 | 17/30 | 14/30 | 3,482 | 3,318（−4.7%） |
| 合计 | 46/90 | 47/90 | 10,637 | 9,901（−6.9%） |

通过率三次有正有负，合计只多 1 个 task-run，不写成质量碾压。请求下降三次方向一致。30 题是定向 canary，不是 Full-113 的自然分布。

## 2. Claim Reuse

### 2.1 r8 四臂对照

r8 在 DeepSWE v1.1 上跑 `verified_producer_only` 四臂，111 题，Pier 通过。主对照是按需 claim 对无 claim 基线。

| 臂 | Pier 通过 | 输入 token | 输出 token | 模型请求 | 题均请求 |
| --- | ---: | ---: | ---: | ---: | ---: |
| A | 72/111（64.86%） | 2,183,995,907 | 18,908,933 | 13,221 | 119.1 |
| `B_empty` | 63/111（56.76%） | 2,290,656,202 | 19,728,252 | 13,532 | 121.9 |
| **`B_claim`** | **73/111（65.77%）** | **1,927,317,486** | **19,002,375** | **12,141** | **109.4** |
| `B_forced_claim` | 65/111（58.56%） | 1,893,296,192 | 18,986,467 | 12,124 | 109.2 |

按需 claim 是四臂里通过率最高的一臂（73/111），比无 claim 多 10 题、高 9.0 个百分点，并与 producer 臂 A（72/111）持平。强制注入通过 65/111，只比基线多 2 题，说明收益主要来自模型按需取用，而不是把同一批 claim 一律塞进上下文。

成本上，`B_claim` 相对 `B_empty` 全面更省：输入少 3.63 亿 token（−15.9%），请求少 1,391 次（−10.3%），输出少 3.7%。111 题配对里，78 题输入更低、73 题请求更少。题均请求从 121.9 降到 109.4。强制臂的输入和请求同样低于基线，但通过率几乎不涨，所以不把它写成质量优势。

| 配对（`B_claim` − `B_empty`） | 题均差 | 中位差 | claim 更低的题数 | 相对变化 |
| --- | ---: | ---: | ---: | ---: |
| 输入 token | −3,273,322 | −2,372,801 | 78/111 | −15.9% |
| 输出 token | −6,539 | −2,857 | 58/111 | −3.7% |
| reasoning token | −4,432 | −2,245 | 59/111 | −3.2% |
| 模型请求 | −12.5 | −12 | 73/111 | −10.3% |

通过率配对：claim 独过 20、独挂 10、双过 53、双挂 28。双侧 exact McNemar p ≈ 0.099。方向一致，尚未跨过 0.05。适合作为 r8 的主结论来展示，不写成已经统计显著的全量碾压。

### 2.2 Claim 命中与「用上才涨分」

`B_claim` 111 题漏斗：

| 事件 | 题数 | 条数 |
| --- | ---: | ---: |
| bundle 可用 / 检索到 / 注入 | 55/111 | 注入 240 条 |
| 判定 `used` | 46/111 | 用上 169 条 |

按是否真正用上 claim 切开，对照仍是同题 `B_empty`：

| 子集 | n | `B_empty` | `B_claim` | 独过 / 独挂 |
| --- | ---: | ---: | ---: | ---: |
| 注入成功 | 55 | 37/55 | **47/55** | 13 / 3 |
| 判定 used | 46 | 30/46 | **39/46** | 11 / 2 |
| A 已 Pier 通过 | 72 | 49/72 | **60/72** | 16 / 5 |

used 子集上，输入 token 题均约 −290 万（33 题更低），请求题均 −12.1（31 题更少）。复用信号和成本下降出现在同一批「claim 进入上下文」的题目上，而不是靠把失败经验灌进全量消费者。

### 2.3 成功 producer 的条件效应

一次已完成的 Standard Full-113（claim-delivery 优化，严格通过）按 producer 是否通过 verifier 分层。全量总分没有 uplift（见附录），但成功 producer 且产出 claim 的 40 题上：

| 对照 | `B_empty` | Claim arm | 差 | 独过 / 独挂 | exact p |
| --- | ---: | ---: | ---: | ---: | ---: |
| `B_claim` | 21/40 | **27/40** | **+15.0pp** | 11 / 5 | 0.210 |
| `B_forced_claim` | 21/40 | **26/40** | **+12.5pp** | 11 / 6 | 0.332 |

失败 producer 仍产出 claim 的 68 题上，按需 / 强制分别为 11/68、12/68，对照 24/68，明显变差。这支持 ACN 的产品默认：**只把 verifier 通过的 producer claim 送进正常检索**，失败经验隔离，而不是「注入更多上下文」。

### 2.4 跨实验重复的正向案例

严格正向：同一 run、同一题 `B_empty` 失败、claim 臂严格通过，且 `claim_observation.injected=true`。下列三题在三次独立 Full-113 里重复出现。

| 题 | 交付 | `B_empty` | Claim 臂 | 注入记录 | producer 也通过 |
| --- | --- | ---: | ---: | ---: | ---: |
| `arktype-json-schema-refs-dependencies` | on-demand | 0/3 | **3/3** | 3/3 | 3/3 |
| `kcp-go-multiplexed-kcp-streams` | forced | 0/3 | **3/3** | 3/3 | 2/3 |
| `prometheus-transactional-reload-status` | forced | 0/3 | **3/3** | 3/3 | 2/3 |

可复用内容是具体工程约束（递归 `$ref` 延迟解析、KCP frame 长度与关闭顺序、事务式 reload 状态机），不是泛化提示。它们是案例，不是全量成功率。

## What This Supports, and What It Does Not

可以说：

- ACN Standard 在完整 113 题上达到接近一半的严格通过，并能与 MiniSWE 同场对照。
- r8 四臂中，按需 claim 比无 claim 多过 10 题，输入 token 少 16%，请求少 10%。
- claim 用上之后，通过率差距进一步拉开；失败 producer 的 claim 会伤害后续解题，所以质量门控是机制的一部分，不是事后补丁。
- Pi-like 在 30 题 × 3 次上保持通过率，并稳定减少请求和输入。

不可以说：

- 任意 claim、任意注入方式都能提高通过率。强制臂在 r8 上几乎不涨分。
- Pi-like 已在 Full-113 上取得效率或质量优势。
- McNemar p≈0.099 或成功 producer 40 题 p=0.21 已经达到常用显著线。

## Appendix A. Other Closed Full-113 Tables

### A.1 2026-08-30 Standard · claim-delivery 优化 · 全量

四臂 113/113 有效，aggregate `passed`。用来说明：**没有质量门控时，全量 claim 不一定高于 `B_empty`。** 第 2.3 节的 +15pp 来自这次实验的成功 producer 子集，不能代替下表。

| 指标 | A | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 严格通过 | 42/113（37.17%） | 47/113（41.59%） | 42/113（37.17%） | 43/113（38.05%） |
| 模型请求 | 13,191 | 13,668 | 13,189 | 12,639 |
| 输入 token | 2,046,128,531 | 2,274,419,883 | 2,191,873,914 | 1,955,384,454 |

### A.2 成功 producer 子集的跨 run 复核

同一分层（A 通过且产出 claim）在不同闭环 Full-113 上并不总是正：

| 实验 | 有效配对 | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | ---: | ---: | ---: | ---: |
| 08-26 Standard | 54 | 34/54 | 31/54 | 38/54 |
| 08-29 Minimal | 43 | 28/43 | 26/43 | 26/43 |
| 08-30 Standard opt | 40 | 21/40 | 27/40 | 26/40 |

08-30 是最强的正向子集；08-26 / 08-29 同类子集接近或为负。跨 run 不稳定，所以正文以 r8 总表为主，40 题 +15pp 只作为质量门控的条件证据。

## Appendix B. Protocol Notes

- Pass / Pier / Gate 三者分开：Gate `pass` 只表示实验证据齐，不等于解题成功。
- 题均 F2P / P2P / partial 是逐题等权平均，不是把全部测试用例池化。
- Token 为 usage ledger 观测值；若存在 incomplete model response，总量视为下界。r8 四臂的 `audit_incomplete` 均为 0。
- 模型请求按 ledger 实计，不是计费，也不是墙钟。
- `injected` 是客观交付事件；`used` 来自 finalize recap 自报，需与通过率配对一起读。
- 未收录中断、未齐分母、以及样本过小的诊断轮次。

## Citation

```bibtex
@misc{acn-deepswe-eval-2026,
  title        = {ACN on DeepSWE: Coding Harness and Claim Reuse},
  author       = {Agent Claim Network},
  year         = {2026},
  howpublished = {https://github.com/FTShare-Lab/acn-deepswe-eval},
  note         = {DeepSWE v1.1 four-arm evaluation}
}
```
