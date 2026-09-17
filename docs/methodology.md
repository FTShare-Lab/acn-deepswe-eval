# 评测方法

> 状态：Pre-smoke / Smoke / Full 的评测基础设施已实现；真实运行按冻结配置在评测机单独启动并保留
> provenance。结果见仓库首页 [README.md](../README.md)。

本文是本仓库的方法学口径。运行契约以本文与 [README](../README.md) 为准，不把首期方案中的历史实施
要求视为已完成能力。

## 1. 研究问题

我们只跑 ACN，不复跑其他公开 harness。评测回答两个问题：

1. ACN 在无 claim 状态下，DeepSWE 得分、token、成本和 agent step 大致处于什么位置；
2. 同一模型、同一批任务下，第二个全新 agent 通过 router 获得 claim 后，是否优于无 claim 的全新 agent。

重点是第二个问题。ACN 若接近公开榜单是额外收益，不是成败标准。

官方 leaderboard 与第三方评测提供了多种 harness × 模型组合的公开分数，可用来建立坐标系；但这些组合
通常同时更换 harness 与模型，不能视为受控对照。因此“ACN 大概在哪里”可以回答，“分差全部来自 harness”
不能据此断言。

## 2. 数据集与冻结

使用 **DeepSWE v1.1**：113 个真实软件工程任务，覆盖 91 个仓库、5 种语言。每题提供仓库快照和需求，
最终由 program verifier 判断 patch 是否通过。

选择 DeepSWE 的原因：任务就是我们原本想设计的工程场景，不再重复自造数据集；每题都有明确判卷；官方与
第三方已有模型、harness、成本和 step 数据可作参照。

正式评测从冻结的 DeepSWE revision 与 Pier revision 新建 manifest。当前官方对齐组为 DeepSWE
`435ee89ec2f2e2289f33b0da4f992f0b7b7266b9` 与 Pier `0daf53d3599e58c4506cf0bcff5e12c77dc282d2`。任务
清单、verifier、`[[verifier.collect]]` 钩子和容器镜像 digest 随 manifest 一起冻结，避免不同版本混算。
仓库内 `manifests/presmoke-v1.json` 与 `manifests/luna-*.json` 记录的是更早 revision 的历史抽样
artifact，只作历史证据，不得混入当前对齐组。

抽样始终基于稳定排序、固定 seed 的无放回选择：Pre-smoke 5 题、Smoke 30 题、Full 113 题。
`freeze-execution-dataset` 在写入前确认两个 checkout 的精确 revision 与干净工作树，批量生成
`allow_internet = false` 的任务副本，并把每题 source/normalized TOML 与目录 tree hash 一同冻结。

## 3. 官方运行条件

以下配置来自冻结的 DeepSWE 113 个 `task.toml` 及 Pier 的 `mini-swe-agent` adapter。正式评测须重新
冻结实际使用的 revision，不得只记录“DeepSWE v1.1”。

| 项目 | 官方配置 | 含义 |
| --- | --- | --- |
| agent 网络 | `network_mode = "no-network"` | 禁止访问 GitHub、搜索引擎、包仓库等普通公网 |
| verifier 网络 | `network_mode = "no-network"` | 判卷过程也不联网 |
| 网络例外 | Pier 的隔离代理仅转发到模型服务 | task 容器不持有长期模型密钥 |
| agent 工具 | 仅 Bash | 通过 Bash 读写文件、检索代码和运行测试 |
| MCP | `mcp_servers = []` | 不加载 MCP server |
| 跨任务状态 | 无 | 每题使用隔离环境，不继承上一题的 workspace、session 或 memory |
| 题内上下文 | 线性保留 | 本题之前的模型消息和命令结果会继续进入上下文 |
| 命令确认 | `--yolo` | 命令直接执行，不等待人工确认 |
| 交互收尾 | `--exit-immediately` | agent 结束时不等待人工输入 |
| step / cost limit | `0` | adapter 不按步数或累计费用提前停止，由 wall timeout 控制 |
| agent timeout | 5400 秒 | 单题最多运行 90 分钟 |
| verifier timeout | 1800 秒 | 判卷最多运行 30 分钟 |
| verifier 环境 | `environment_mode = "separate"` | 只提取 patch，在全新容器中应用并判卷 |
| 资源 | 2 CPU / 8 GiB / 20 GiB / 0 GPU | agent 与 verifier 使用固定资源 |

`mini-swe-agent` 默认只向模型暴露 Bash；命令结果超过 10,000 字符时只保留前 5,000 和后 5,000 字符。
提示词中即使允许“安装缺失工具”，任务期普通公网仍被拦截，因此只能使用镜像内已有依赖。

DeepSWE 的 `network_mode` 与 Pier 的 `allow_internet` 表达不同。runner 必须在运行前做 fail-closed
转换：仅当 agent / verifier 两者均为 `"no-network"` 时，生成 Pier 兼容副本，并显式写入
`environment.allow_internet = false` 与 `verifier.environment.allow_internet = false`。原始和转换后
配置的 SHA-256 都写入 manifest；转换必须保留 `[[verifier.collect]]`，未经转换的任务禁止运行。

## 4. ACN 对齐配置

ACN 不伪装成 `mini-swe-agent`，其原生文件、命令和 router 工具属于待测 harness；但环境边界必须对齐，且
`A`、`B_empty`、`B_claim`、`B_forced_claim` 除明确的 claim 交付方式外完全相同。

| 项目 | ACN 评测配置 |
| --- | --- |
| 普通公网 | 关闭；`web_search`、`web_fetch`、`web_request` 不注册，Shell 出网由 sandbox 硬拦截 |
| 网络白名单 | task 仅能经 Pier 隔离代理访问模型服务主机名；router 使用进程内冻结 bundle，maintainer 关闭 |
| 依赖 | 预装进镜像；运行中禁止从 GitHub、PyPI、npm 等下载 |
| MCP | 关闭 |
| Memory | 关闭注入、读取、写入和后台 memory review；每个 attempt 使用全新 `acn_home` |
| Session | 不 resume；每题、每臂使用新的 agent id、session id 和 session 目录 |
| Workspace | 从同一 base commit / image digest 创建 pristine 副本；臂间不共享 git 对象外的运行产物 |
| Claim | 按第 5 节的可见性矩阵配置；B 不能看到 A 的 patch、session、trace、日志或私有文件 |
| Skill | 四臂注入完全相同的 `coding-benchmark` skill，记录全文 SHA-256 |
| Prompt | 相同 system prompt、首条任务 prompt 和注入顺序；runtime `ACN.md` 只承载相同的 claim 交付契约；禁止中途人工补充提示 |
| 工具 | 四臂工具 schema、权限、并发上限和输出截断相同；除 router 返回内容外不得因组别变化 |
| 人工交互 / 终止 | 关闭 `ask_user` 和 TUI user shell；完成后应调用无参数 `submit_task`；只有正常、可消费的 assistant 最终回复可在遗漏该调用时作为隐式完成 |
| Subagent | 关闭，避免引入额外模型实例和未计量的共享状态 |
| 超时 / 资源 | 官方对齐组：agent 5400 秒、verifier 1800 秒，ACN 工作 deadline 5280 秒（收尾预留 120 秒）；均为 2 CPU / 8 GiB / 20 GiB / 0 GPU |
| step / cost limit | 不设置早于所属 agent timeout 的停止线 |
| verifier | 与 agent 分离；只应用最终 patch，在 pristine 容器中离线判卷 |

网络必须由 runner / sandbox 强制执行，不能只在 prompt 中要求模型“不要联网”。

评测生成的 `acn.toml` 将 `max_parallel_tool_calls` 设为 `5`、`file_diff_max_changed_lines` 设为
`200`、`file_read_max_chars` 与 `code_run_max_output_chars` 设为 `20000`，`auto_compact_ctx_ratio`
为 `0.80`；`code_run` 观察窗口仍用产品内部护栏。这些有效值随 provenance 冻结。

### 4.1 完成语义

ACN 不把任意“模型不再调用工具”当作完成。evaluation profile 额外暴露无参数的 `submit_task`，且它必须是
一个 assistant 响应中的唯一工具调用。其成功执行后 turn loop 立即结束，不再把 tool result 回灌给模型
或发起下一次 provider request；之后才开始 session finalize 与 Pier verifier。

`submit_task` 是首选的明确终止信号，但不是 claim 收尾的硬门槛：`run_turn` 正常结束而未提交时，评测
记录 `evaluation_completion.mode=implicit_assistant_done`，再进入相同的 finalize 与 verifier 路径；
显式提交记录 `mode=explicit_submit_task`，并保留 `evaluation_submitted` 事件。provider 截断、无可消费
输出、中断、请求错误和 deadline 都不能走隐式完成，仍记为 agent failure。事件账本区分显式与隐式完成，
便于评估不同模型的提交遵从率。

`agent_seconds` 同时驱动 Pier 的墙钟、ACN 单次请求 timeout 与 attempt 自有 deadline；后者必须预留
至少 `deadline_reserve_seconds`（示例 120 秒）给 session finalize、事件账本与 result 写入。任何扩展
预算仅用于诊断，不与官方对齐组混算。

### 4.2 运行中监控

宿主在 attempt 运行期间只读轮询 session `turn_events.jsonl`，把最后活动时间、最近事件和疑似停滞状态
写入 attempt 的 `progress.json`。该监控不提前停止 agent：模型长推理、上游排队或工具运行都必须继续到
原有 deadline。运行被人为中止时，manifest 和 progress 记录 `INTERRUPTED_BY_OPERATOR`；缺少最终 result
不能单独作为“模型无响应”或 claim 逻辑失败的证据。

上游若以 HTTP 429 并明确返回“并发容量耗尽”的机器可读代码，Rust result 写入稳定的
`failure_kind=upstream_concurrency_exhausted`。宿主将其记为基础设施失败，保留 result、event ledger
和运行进度，但不经过 Gate、freeze 或后续 B 臂，也不混入 agent、claim、verifier 指标。不能只凭 HTTP
429 泛化该归因。

## 5. 四臂与 claim 可见性

每道题先运行 `A`；`A` 完成并退出后，由宿主写入不可变 freeze barrier，只采信 barrier 前的宿主事件
账本冻结 claim bundle。随后从 pristine workspace 启动三个彼此隔离的 B 臂。

| 组别 | 作用 | 可见信息 |
| --- | --- | --- |
| `A`（producer） | 第一次正常运行，同时产出 claim | 无历史 claim |
| `B_empty` | 全新 agent，对照组 | router 可用，但 bundle 为空 |
| `B_claim` | 全新 agent，实验组 | 只能通过 router 获取 A 的冻结 claim；system context 展示有界 claim 摘要目录，正文由模型自主调用 `consult_router` 一次取回 |
| `B_forced_claim` | 全新 agent，受控交付组 | 首轮任务上下文附有同一冻结 router 检索的完整 claim，明确标为需独立验证的前序信息 |

| 状态 | `A` | `B_empty` | `B_claim` | `B_forced_claim` |
| --- | --- | --- | --- | --- |
| 历史 Memory / Session | 空 | 空 | 空 | 空 |
| 初始本地 Claim | 空 | 空 | 空 | 空 |
| Router | 进程内空 bundle | 进程内空 bundle | 进程内只读 bundle，仅含 A 本题 barrier 前的 claim | 同 `B_claim` |
| 首轮任务上下文 | 无 claim | 无 claim | 无 claim（模型自主检索） | 同一冻结 router 查询所得完整 claim |
| A 的 workspace / patch / log / trace | 自身可见 | 不可见 | 不可见 | 不可见 |
| 运行中团队数据变化 | 不读取历史 claim | 禁止 | 禁止；开始前生成只读快照 | 禁止；开始前生成只读快照 |

`B_claim` 与 `B_forced_claim` 的唯一差别是 claim 是否由模型自主检索；两者均由同一冻结 router 产生可
校验的 content hash 归因。B 运行期间不得继续接收 A 的新 claim、policy 或 dispute 更新。

### 5.1 claim 质量门控与分层

默认 `claim_quality_gate=verified_producer_only`：只交付正常完成且通过 verifier 的 producer claim。
失败 producer 的 claim 被隔离（bundle manifest 记录 `quarantined_claim_ids`），两个带 claim 的 B 臂
拿到空 bundle；显式写 `"none"` 才会把失败 producer 的 claim 交付给 consumer，只用于隔离研究。

`run_all_variants_without_claims=true` 时每题实际执行四臂：若 A 没有 eligible claim，freeze barrier
仍产出可审计的空 bundle，两个带 claim 的 B 臂照常执行并记录 `EMPTY_CLAIM_BUNDLE`，绝不伪造或借用其他题
的 claim。未开启该开关时保留历史的“两个带 claim B 臂不适用”行为。

统计按 producer 结果分层：

| 分层 | 入组条件 | 主要问题 |
| --- | --- | --- |
| `success_efficiency` | A 通过 verifier，且 bundle 非空 | 自主检索与强制交付的 claim 能否减少 agent step、成功响应观测 token 和耗时，同时维持完成质量 |
| `failure_recovery` | A 未通过 verifier，且 bundle 非空（仅 `claim_quality_gate=none`） | 失败中的观察、已排除路径和测试结果能否让 claim 臂比干净重试更常通过 verifier |
| `failed_producer_quarantine` | A 未通过 verifier，claim 被隔离 | 保留四臂得分与用量，不参与 claim 效果配对 |
| `unpaired_no_claim` | bundle 为空 | 记录 claim 产出覆盖率，不进入 claim 对照统计 |

两个分层绝不混合计算 uplift。失败 claim 不被当作已验证事实：它们只能作为带 provenance 的冻结观察供 B
自主判断。

### 5.2 自适应 producer 选择

`claim_producer_variant=adaptive` 从同批任务的两个无 claim 臂中按预注册规则选出 producer，其基线是
另一个臂。该选择依赖观测结果，属于探索性分析，不能把该基线称为未经选择的独立 baseline，也不能把其
配对 p 值直接解释成预注册固定 producer 实验的因果证据。

## 6. 统一 skill

四臂使用同一份 `assets/coding-benchmark/SKILL.md`，补足轻量 harness 缺少的通用工作流：阅读任务和
仓库 → 复现问题 → 定位原因 → 实现修复 → 跑针对性测试 → 按错误返工 → 检查 diff → 最终验证 →
`submit_task`。skill 不包含题目答案或仓库专属提示；评测期间 skill 原文、模型配置和预算保持不变，
其目录 tree hash 写入 provenance。

## 7. 模型与调用渠道

模型访问完全沿用 Pier 官方 adapter 的做法，不自建代理或 broker：模型 key 从宿主环境变量
`ACN_EVAL_UPSTREAM_KEY` 读取，仅以容器变量 `ACN_EVAL_MODEL_KEY` 交给 `acn_eval`；`acn_eval` 启动后经
匿名 pipe 原位 re-exec 清除初始环境，key 不进 argv、配置文件、manifest 或 JSONL。出网由 Pier 的 Squid
域名 allowlist 限死，只允许 `ACN_EVAL_UPSTREAM_BASE_URL` 的主机名。

`model` 是发送给模型服务的请求模型名，`response_model` 是上游实际返回的 checkpoint 名，二者都写入
provenance；Gate 核对每次响应回显的模型名与 `response_model` 一致。若预探针发现响应 checkpoint 不同，
必须以实际值更新配置，不能静默忽略别名映射。`reasoning_effort` 必填；官方可比组使用 `max`，其他值须在
provenance 中标为非官方对齐配置。

token 计量由 `acn_eval` 从上游响应的 `usage` 累计，写进 `result.json`：`model_requests`、
`turn_model_requests`、`finalize_model_requests`、`complete_model_responses`、
`incomplete_model_responses`、`response_models`、`input_tokens`、`output_tokens`、
`cache_read_tokens`、`reasoning_tokens`；宿主另计算 `cache_hit_rate`。**reasoning token 计入
`max_tokens`**：`max_tokens` 设小会让模型在发出 tool call 前被截断。官方 `mini-swe-agent` 不设 output
cap，本 runner 默认给 65536。

单次可重试请求若在收到响应前中断，保留为 `incomplete_model_responses` 审计告警，不因而否定已完成的
agent / verifier 结果；成功响应的 usage 必须完整。token 与费用在这种情况下标为“成功响应观测值下界”，
并按 arm 报告不完整请求数，不把未知的中断请求成本补零或伪造。

## 8. 每个 attempt 必须落盘

每个 attempt 生成不可修改的 provenance 与 manifest，至少包含：

- DeepSWE、Pier、ACN、runner 源码、skill 的 revision / tree hash，以及 `acn_eval` 二进制 SHA-256；
- task id、source / normalized task 目录 tree hash、agent / verifier image digest 和资源限制；
- provider、请求模型名、响应 checkpoint、reasoning effort、采样参数、context window、`max_tokens`、
  retry 策略、模型出口模式；
- enabled tools、并发工具数、file / code-run 输出上限、compact 阈值；
- agent / verifier timeout、退出原因、runner / proxy / network 异常；
- input / output / cache / reasoning token、完整与不完整模型请求数、agent step；
- patch hash、verifier 结果、router evidence（候选 / 选中 / 注入的 claim id 与内容 hash）和实际使用的
  claim id。

缺少 manifest、配置 hash 对不上或发生白名单外联网的 attempt 不进入正式统计。

## 9. Gate 判什么

Gate 只验证基础设施、claim 归因与隔离：artifact hash、verifier 是否真的跑过、usage 是否完整上报、
响应模型名、Pier task checksum / trial 隔离，以及 `B_empty` 不得见到任何 claim、带 claim 的两个 B 臂
只能使用冻结 bundle 内的 claim。

**verifier 判 0 分与 agent 自身失败都是有效实验结果，不是 Gate 失败**，按未通过计分，不得重跑刷分。
`verifier_passed` 只有 agent 正常完成且 verifier 通过才为 true；原始 patch 判卷保留在
`pier_trial` / `verifier_regrade`。已知 verifier 基础设施故障只允许冻结 patch 重判一次，不重跑 agent。
agent 异常、截断或 deadline 按未通过计分，即使其 patch 的原始 verifier reward 为 1。

`run_class=formal` 表示满足本 runner 的冻结与隔离要求：`model_egress_mode=pier`、锚定的
`acn_main_revision` / `acn_version`、官方镜像、磁盘准入下限等。它仍需核对资源、harness 和预算，才能
判断是否与外部榜单同口径。`diagnostic` 用于比较不同 ACN revision 或非官方预算，不得改称 formal score。

## 10. 记录什么

| 指标 | 用途 | 来源 |
| --- | --- | --- |
| 成功率 | 每臂 verifier 通过数 / 冻结 task 数；分母固定，缺失或失败 task 单列原因 | attempt result + `cohort_coverage` |
| 配对差 | `B_claim − B_empty`、`B_forced_claim − B_empty`、consumer − producer 的同题配对，含 wins / losses 与双侧精确 McNemar 检验 | `paired_against_no_claim_baseline` / `paired_against_producer` |
| 成功效率 | 同题均通过样本的 agent step、成功响应观测 token、耗时差 | `success_efficiency` 分层 |
| token | 成功响应返回的原始 usage；中断请求单列计数，不补零 | Rust `result.json` |
| agent step | 一次完整的模型响应；`agent_steps` 含 finalize 响应，跨臂比较交互效率应用 `turn_model_requests` | ACN 事件账本 |
| claim funnel | bundle 可用、router 检索、内容注入、模型报告使用及对应 claim 数 | attempt 记录 + aggregate |

当前没有自动生成冻结费率费用、耗时配对或 95% 置信区间；已有同题成功率差和精确 McNemar 检验不替代
这些报告项。费用若按官方费率换算须单列，不与实际 GPU 成本混成一个数。

## 11. 运行规模

| 阶段 | 规模 | 目的 |
| --- | ---: | --- |
| Pre-smoke | 5 题 × 4 臂 = 20 attempts | 验证端到端协议、隔离、计量和 claim 归因 |
| Smoke | 30 题 × 4 臂 = 120 attempts | 验证预算、无 claim 基线、自主检索和强制交付方向 |
| Full | 113 题 × 4 臂 = 452 attempts | 形成全量结果 |

每个 task / arm 只允许一次解题运行。单次可重试模型请求的中断由 agent 内部 retry 处理，并作为非阻断
审计告警留存；只有明确的 runner、容器、网络或 proxy 故障可以原配置重试一次，并保留失败 attempt。
若 Smoke 后模型、skill、预算和执行协议不变，保留这 30 题结果，Full 只补剩余 83 题；只有 Smoke 暴露
出协议错误并导致配置修改时，受影响的题才需要重跑。

Smoke 完成后检查：verifier、router、session JSONL 和成功模型响应 usage 均能稳定落盘；无 claim 基线
没有出现全失败或全通过；`B_claim` 能实际检索到 claim；token 与费用可复算且全量预算可接受；至少一个
分层出现值得继续验证的信号。30 题只用于做投入判断，不发布强结论。Full 报告按题配对的得分差，并附
不确定性估计。

## 参考

- [DeepSWE 官方页面](https://deepswe.datacurve.ai/)
- [DeepSWE GitHub](https://github.com/datacurve-ai/deep-swe)
- [DeepSWE task.toml 配置示例](https://github.com/datacurve-ai/deep-swe/blob/435ee89ec2f2e2289f33b0da4f992f0b7b7266b9/tasks/true-myth-iterable-collection-combinators/task.toml)
- [Pier](https://github.com/datacurve-ai/pier) 与其
  [mini-swe-agent adapter](https://github.com/datacurve-ai/pier/blob/0daf53d3599e58c4506cf0bcff5e12c77dc282d2/src/pier/agents/installed/mini_swe_agent.py)
- [mini-swe-agent](https://github.com/SWE-agent/mini-swe-agent) 及其
  [mini.yaml](https://github.com/SWE-agent/mini-swe-agent/blob/a83fcae82d2a08f0ee0c688f9d137b3566c097f8/src/minisweagent/config/mini.yaml)
- [Artificial Analysis coding agents 方法](https://artificialanalysis.ai/methodology/coding-agents-benchmarking)
