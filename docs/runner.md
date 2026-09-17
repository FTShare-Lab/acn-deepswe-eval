# ACN DeepSWE 评测 Runner

[English](../README_EN.md) · [评测报告](../README.md)

本仓库是 [Agent Claim Network（ACN）](https://github.com/FTShare-Lab/agent-claim-network) 在
[DeepSWE](https://deepswe.datacurve.ai/) 上的可审计评测 runner。它在冻结的 DeepSWE / Pier revision 上，
为每道题运行 ACN 的四个臂，用 DeepSWE 官方 program verifier 判卷，并把任务冻结、模型访问、claim 隔离、
用量计量与结果归因的每一步都落成可重建的证据。

DeepSWE v1.1 由 [Datacurve](https://github.com/datacurve-ai/deep-swe) 维护：113 个从活跃开源仓库
新写的长程软件工程任务，覆盖 91 个仓库、5 种语言，每题在隔离容器中运行，由手写的行为级 verifier
判定 patch 是否通过；官方用 [Pier](https://github.com/datacurve-ai/pier) 执行任务并统一以
mini-swe-agent 跑榜。本 runner 复用 Pier 的任务格式、容器隔离、网络 allowlist 与 verifier，只把
agent 换成 ACN。

评测回答两个问题：ACN 在无 claim 状态下的 DeepSWE 得分、token 与 agent step 大致处于什么位置；同一
模型、同一批任务下，第二个全新 agent 通过 router 获得前一个 agent 冻结的 claim 后，是否优于无 claim
的全新 agent。方法学口径见 [methodology.md](methodology.md)，结果见仓库首页 [README.md](../README.md)。

## 四臂设计

每道题先运行 `A` 与 `B_empty`，`A` 完成后由宿主写入不可变 freeze barrier 并冻结 claim bundle，再从
pristine 工作区运行两个带 claim 的 B 臂：

| Arm | 作用 | claim 如何到达模型 |
| --- | --- | --- |
| `A` | producer；独立解题并产出可冻结的 claim | 无前序 claim |
| `B_empty` | 无 claim 的同题基线 | 完全没有 claim |
| `B_claim` | 自主检索的真实端到端路径 | 冻结 router 可用，system context 只展示有界摘要目录；是否调用 `consult_router` 取回正文由模型决定 |
| `B_forced_claim` | 受控对照 | 框架按 bundle 查冻结 router，把同一批 claim 附到首轮任务上下文 |

主比较是 `B_claim` 与 `B_forced_claim` 分别相对 `B_empty` 的同题配对差。B 臂不能看到 A 的 patch、
工作区、session、日志或私有 memory；除 claim 交付方式外，四臂的 system prompt、skill、工具、预算与
verifier 完全相同。默认 `claim_quality_gate=verified_producer_only`：producer 未通过 verifier 时其
claim 全部隔离，两个带 claim 的 B 臂拿到空 bundle 并记录 `EMPTY_CLAIM_BUNDLE`，不伪造或借用其他题的
claim。

## 与官方口径的关系

- **模型访问**沿用 Pier 官方 adapter 的做法，不自建代理或 broker。模型 key 从宿主环境变量
  `ACN_EVAL_UPSTREAM_KEY` 读取，仅以容器变量 `ACN_EVAL_MODEL_KEY` 交给 `acn_eval`；进程启动后经匿名
  pipe 原位 re-exec 清除初始环境，key 不进 argv、配置文件、manifest 或 JSONL。
- **出网**由 Pier 的 Squid 域名 allowlist 限死，只允许 `ACN_EVAL_UPSTREAM_BASE_URL` 的主机名；agent 与
  verifier 的 `allow_internet` 均为 `false`；`code_run` 子进程会剥掉 key 变量。
  `model_egress_mode` 是冻结启动配置的一部分，默认且唯一可作为正式结果的值是 `"pier"`；`"direct"`
  仅供诊断模型连通性，会被 manifest 记录并使 formal Gate 失败。
- **用量**由 `acn_eval` 从上游响应的 `usage` 累计写入 `result.json`，宿主另算 `cache_hit_rate`。
  reasoning token 计入 `max_tokens`；官方 mini-swe-agent 不设 output cap，本 runner 默认 65536。
- **完成语义**：evaluation profile 暴露无参数的 `submit_task`，模型完成实现、测试与 diff 检查后应把它
  作为唯一工具调用；提交后不再请求模型，随后运行 session finalize 与 Pier verifier。正常最终回复遗漏
  该调用时记录 `implicit_assistant_done` 并走同一路径；截断、异常、无可消费输出和 deadline 仍为 agent
  failure。
- **资源与超时**：官方对齐组为 2 CPU / 8 GiB / 20 GiB、agent 5400 秒、verifier 1800 秒；ACN 工作
  deadline 预留 120 秒收尾。任何扩展预算都只能标为 diagnostic。

四臂并非官方单 agent 榜单的直接复刻，不得把本 runner 的结果与外部公布分数当作同口径排行榜比较。

## 仓库结构

```
src/acn_deepswe/        runner 源码（仅标准库；datacurve-pier 为真实执行的 optional dependency）
  dataset.py            任务冻结与 tree hash
  network.py            DeepSWE network_mode → Pier allow_internet 的 fail-closed 转换
  plan.py               确定性 attempt plan
  provenance.py         不可变 provenance 与目录 tree hash 算法
  pier_adapter.py       Pier BaseAgent 适配：上传、allowlist、模型出口、单 attempt 执行
  host_runner.py        单题四臂宿主编排：producer wave → freeze → consumer wave
  claim_freeze.py       基于 freeze barrier 的 claim bundle 冻结
  gate.py               机器可判定的基础设施 / 归因 / 隔离门禁
  rust_contract.py      Rust acn_eval 产物（result.json / events.jsonl）的定版解析
  presmoke.py           多题调度与 aggregate（配对、分层、claim funnel）
  presmoke_cli.py       acn-deepswe-presmoke：按冻结 manifest 启动、dry-run、续跑
  auto_run.py           acn-deepswe-auto：prepare / run / monitor 自动化编排
  cli.py                acn-deepswe：freeze / plan / validate-config 等审计型命令
  resource_guard.py     Docker 全局互斥、容量门禁与遗留清理
tests/                  unittest 套件与 Rust 契约 fixture
manifests/              示例启动配置（*.example.json）与历史冻结 manifest
assets/coding-benchmark 四臂共同注入的冻结 skill
docker/                 交叉编译 Linux x86_64 acn_eval 的 builder
docs/                   方法、运行指南、契约与结果
```

## 快速开始

### 依赖

- Python 3.12+；Docker daemon（Linux amd64 或 arm64 宿主均可，macOS Docker Desktop 亦可）。
- DeepSWE checkout 与 Pier checkout，均处于冻结 revision 且工作树干净。Pier 以 editable 方式安装进
  自己的 venv，`pier_executable` 必须是该 venv 的 `bin/pier`，其 PEP 610 `direct_url` 须指向
  frozen Pier checkout。
- ACN checkout（构建 `acn_eval` 的源码，见 [acn_integration.md](acn_integration.md)）。

### 安装 runner

```sh
git clone https://github.com/FTShare-Lab/acn-deepswe-eval
cd acn-deepswe-eval
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -e .
PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_*.py'
```

### 构建 Linux `acn_eval`

```sh
sh docker/build-acn-eval-amd64.sh --acn-checkout /absolute/path/to/agent-claim-network
```

产物固定为 Linux x86_64 ELF，位于 `<acn_checkout>/target/deepswe-linux-amd64/release/acn_eval`。

### 冻结任务

```sh
acn-deepswe validate-config /absolute/DeepSWE/tasks/<task> /absolute/checked
acn-deepswe freeze-execution-dataset /absolute/DeepSWE/tasks \
  /absolute/runs/current/frozen-manifest.json /absolute/runs/current/normalized \
  --deepswe-checkout /absolute/DeepSWE --pier-checkout /absolute/pier \
  --seed 17 --sample-size 30
acn-deepswe plan /absolute/runs/current/frozen-manifest.json /absolute/runs/current --seed 99
```

`validate-config` 做 fail-closed 网络转换：只有 `agent.network_mode` 与 `verifier.network_mode` 均为
`"no-network"` 时才生成 Pier 兼容副本，并对两个环境写入 `allow_internet = false`；转换保留
`[[verifier.collect]]`，源与结果的 SHA-256 一并输出。`freeze-execution-dataset` 在写入前确认两个
checkout 的精确 revision 与干净工作树，批量生成离线任务副本并冻结每题 TOML 与目录 tree hash；已有
manifest 或 normalized 目录时拒绝覆盖。`--sample-size 5` 用于 Pre-smoke，`30` 用于 Smoke，`113` 为
全量；抽样始终是稳定排序、固定 seed 的无放回选择。`plan` 从冻结 manifest 生成四臂 attempt plan。

### 启动配置与 dry-run

复制 [manifests/presmoke-run.example.json](../manifests/presmoke-run.example.json) 到仓库外的绝对路径，
填入两份 checkout、`acn_checkout`、Linux `acn_eval`、本仓库的 `assets/coding-benchmark`、冻结模型名与
资源预算。**配置中不得放 credential**；它只从宿主环境读取。示例中的 `frozen-model-alias` /
`frozen-model-checkpoint` 是占位值。

```sh
ACN_EVAL_UPSTREAM_BASE_URL=<https-url> \
acn-deepswe-presmoke --config /absolute/path/to/presmoke-run.json --dry-run
```

dry-run 静态校验两份 checkout revision、`acn_checkout` 与 `acn_revision` 的绑定、source/normalized
完整 task 目录 tree hash 和全部四臂计划，不执行 Linux 二进制，也不调用 Docker。

### 真实执行

```sh
ACN_EVAL_UPSTREAM_BASE_URL=<https-url> ACN_EVAL_UPSTREAM_KEY=<key> \
acn-deepswe-presmoke --config /absolute/path/to/presmoke-run.json
```

不希望把 key 写进 shell 历史时用 `--read-key-stdin` 按提示隐藏输入；它只在真实执行且环境无该变量时
读取，进程退出时清除。真实执行在创建任何 attempt 目录前硬性检查：Pier 可执行文件与 checkout 的绑定、
`pier --help`、Docker daemon、每个 task 镜像能解析为本地 content digest、Pier egress proxy 镜像
digest 一致，以及 Docker 的 `NCPU` / `MemTotal` 足以容纳 `task_workers × cpus` 与
`task_workers × memory_mb`。资源不足直接失败，不静默降低并发。

preflight 通过后，runner 把 `acn_deepswe`、Pier package、console script、coding skill 与 `acn_eval`
一次性复制到 `output_dir/frozen-python/`（只读），四臂只从该目录 import，并在每臂前复核二进制、skill、
task 与两份 Python source tree hash。冻结 manifest 中的每题按 producer / consumer 两波执行，波内可
并行；全部题目和 arm 共用 `task_workers` 个 attempt 许可，Pier trial `max_retries=0`。基础设施或 Gate
失败以非零退出，但不会自动重试 solve。

Pier 固定 `force_build=false`（使用冻结 `task.toml` 指向的官方预构建镜像）与 `delete=false`（trial
结束拆掉 Compose 容器但保留本地镜像），`n_attempts=1`、`n_concurrent_trials=1`。

### 自动化与监控

Smoke 后补齐全量、直接全量、先 A 后 B 的两阶段、adaptive producer 选择与只读监控由
`acn-deepswe-auto` 承载，见 [automated_run.md](automated_run.md) 与
[solver_aligned_run.md](solver_aligned_run.md)。比较两个 ACN revision 的配对实验见
[claim_harness_experiment.md](claim_harness_experiment.md)。

## 启动配置参考

`acn-deepswe-presmoke` 的配置字段（未列出的字段会被拒绝）：

| 字段 | 说明 |
| --- | --- |
| `frozen_manifest` / `attempt_plan` / `normalized_root` / `output_dir` | 冻结 manifest、attempt plan、离线任务副本与宿主输出目录，均为绝对路径 |
| `deepswe_checkout` / `source_tasks_root` / `pier_checkout` / `pier_executable` | 冻结的 DeepSWE、任务根目录、Pier checkout 与其 venv 的 `bin/pier` |
| `acn_checkout` / `acn_eval` | 构建 `acn_eval` 的 ACN checkout（HEAD 必须等于 `acn_revision` 且干净）与 Linux 二进制 |
| `acn_revision` / `acn_main_revision` / `acn_version` | 评测 commit、产品基线 commit 与版本；`formal` 固定锚定 `9b818d70…` / `0.2.5` |
| `frozen_skill` | 含 `SKILL.md` 的完整 skill 目录，四臂注入相同内容，hash 写入 manifest |
| `pier_egress_proxy_image` / `pier_egress_proxy_content_digest` | Pier Squid 代理镜像及其 content digest；`formal` 固定 `pier-egress-proxy:ubuntu-24.04` |
| `model` / `response_model` / `reasoning_effort` | 请求模型名、上游实际回显的 checkpoint、推理强度 |
| `run_class` | `formal` 或 `diagnostic` |
| `model_egress_mode` | `pier`（正式）或 `direct`（诊断） |
| `harness_mode` | `standard`（默认）、`minimal`、`concise`、`pi_like`、`open_code_like`；非 standard 仅用于机制对照 |
| `claim_quality_gate` | `verified_producer_only`（默认）或 `none` |
| `file_edit_authority_enabled` | 是否启用 ACN 的文件修改许可校验 |
| `resources` | `cpus`、`memory_mb`、`storage_mb`、`max_tokens`、`context_window` |
| `timeouts` | `agent_seconds`、`deadline_reserve_seconds`、`verifier_seconds`；`agent_seconds` 同时覆盖 Pier 墙钟、ACN 请求 timeout 与 attempt deadline |
| `llm_retry` | `retry_count`、`retry_base_delay_ms`、`retry_max_delay_ms` |
| `progress` | `poll_secs`（默认 30）、`stall_after_secs`（默认 600）；只标记疑似停滞，绝不自动终止 |
| `host_capacity` | `memory_reserve_mb`、`disk_reserve_mb`、`disk_admission_mb_per_worker`（`formal` 不小于 8192） |
| `task_workers` | 全局并发 attempt 许可，默认 1 |
| `cleanup_stale_pier_resources` | 启动前清理已停止且带 Pier Compose 证据的遗留容器及其生成镜像，并核对 egress proxy 镜像 digest |
| `run_all_variants_without_claims` | 无 eligible claim 时仍执行两个带 claim 的 B 臂并标记空 bundle |
| `run_a_only` / `b_only_from_a_output_dir` | 先 A 后 B 的两阶段接续 |
| `claim_producer_variant` / `producer_pair_only` / `adaptive_source_output_dir` / `producer_selection_manifest` | `A`（默认）或 `adaptive` 两阶段 producer 选择 |

`acn-deepswe-auto` 在此基础上以 `run_root`、`smoke_size`、`full_size`、`dataset_seed`、
`smoke_plan_seed`、`full_plan_seed`、`adaptive_producer_selection`、
`reuse_local_agent_image_fingerprint` 替代由它生成的 manifest / plan / 输出路径与 `acn_revision`。

## 产物

每个 attempt 的 `output_path` 下：`host-config/`（attempt TOML、ACN config、Pier job 与 trial）、
`gate.json`、`attempt-result.json`、`progress.json`。Pier trial 下的
`agent/evaluation/{result.json,events.jsonl}`、`artifacts/model.patch` 与 pinned `TrialResult` 会被
引用并解析。attempt TOML 固定 `workspace_root=/app`、`runtime_root=/logs/agent/runtime`、
`output_dir=/logs/agent/evaluation`、`acn_config=/opt/acn-eval/acn.toml`；`B_claim` 与
`B_forced_claim` 设置 `claim_bundle=/opt/acn-eval/claims.json`。

`attempt-result.json` 记录 `status`、`verifier_passed`、`agent_steps`、`usage`、`gate`、`pier_trial`、
`verifier_regrade`、`failure_kind` 与带 `stage=` 前缀的 `agent_error`。`verifier_passed` 只有 agent
正常完成且 verifier 通过才为 true；若 Rust result 标记 `failure_kind=upstream_concurrency_exhausted`
（HTTP 429 且上游给出并发容量耗尽代码），宿主记为基础设施失败，保留证据但不执行 Gate、freeze 或后续
B 臂。

`progress.json` 每 `poll_secs` 原子写入 session 事件路径、事件数、最后活动时间与最近事件类型；连续
`stall_after_secs` 无事件标记 `possibly_stalled`，仅提示人工排查。人为中止记录
`INTERRUPTED_BY_OPERATOR`。

`output_dir/presmoke-aggregate.json` 汇总全部 task：`cohort_coverage`（planned / included / excluded 与
排除原因，分母固定为冻结 task 集）、按 producer 结果分层的 `cohort_metrics`（各臂通过数、用量总和 /
均值、`empty_claim_bundle_attempts`）、两组同题配对 `paired_against_producer` 与
`paired_against_no_claim_baseline`（含 wins / losses 与双侧精确二项检验 `exact_mcnemar_p`），以及
`claim_funnel`（每臂 bundle 可用、router 检索、内容注入、模型报告使用及对应 claim 数）。各题
manifest、jobs 与 claim bundle 在 `output_dir/tasks/<task>/`；`task-completions.json` 持久化所有 task
终态。

## Gate 判什么

Gate 只验证基础设施、claim 归因与隔离：artifact hash、verifier 是否真的跑过、usage 是否完整上报、
响应模型名是否等于 `response_model`、Pier task checksum / trial 隔离，以及 `B_empty` 不得见到任何
claim、带 claim 的两个 B 臂只能使用冻结 bundle 内的 claim（候选 ⊇ 选中 ⊇ 注入 ⊇ 使用，内容 hash 一致）。

**verifier 判 0 分与 agent 自身失败都是有效实验结果，不是 Gate 失败**，按未通过计分，不得重跑刷分。
checkpoint 持久化所有 task 终态；普通 `--resume` 遇到任何失败终态即拒绝。只有无终态且已有半成品的
中断 task，才可由操作者显式传 `--resume --retry-interrupted` 重跑一次，此前的产物和 retry 计数都会
保留。

## 结果

见仓库首页 [README.md](../README.md)。

## 文档

- [methodology.md](methodology.md)：数据集、官方口径、ACN 对齐配置、四臂可见性矩阵、分层与指标定义
- [acn_integration.md](acn_integration.md)：ACN 侧文件、`acn_eval` 构建与 CLI、attempt TOML、`result.json` / `events.jsonl` 契约
- [automated_run.md](automated_run.md)：Smoke → Full 自动化、两阶段接续、续跑与监控
- [solver_aligned_run.md](solver_aligned_run.md)：解题对齐全量运行
- [claim_harness_experiment.md](claim_harness_experiment.md)：两个 ACN revision 的异机配对实验协议
- [claim_harness_design.md](claim_harness_design.md)：被评测的 claim harness 变体设计
- [../README.md](../README.md)：评测报告

## 来源

runner 源码剥离自 ACN 仓库 `feature/deepswe-claim-harness` 分支
`778c06756c6afc63f45fe1d1400054fae9c9bcd4` 的 `benchmarks/deepswe/`。独立成仓后唯一的行为改动是：
ACN checkout 不再从 runner 所在路径推断，改由启动配置的 `acn_checkout` 显式指定；构建脚本以
`--acn-checkout` 接收同一路径。Rust 侧的 `acn_eval` 与 evaluation profile 留在 ACN 仓库，锚点见
[acn_integration.md](acn_integration.md)。

## 参与贡献

见 [CONTRIBUTING.md](../CONTRIBUTING.md)。

## 许可证

MIT OR Apache-2.0，见 [LICENSE-MIT](../LICENSE-MIT) 与 [LICENSE-APACHE](../LICENSE-APACHE)。
