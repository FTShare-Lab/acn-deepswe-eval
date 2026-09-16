# ACN 侧集成与 Rust ↔ Python 契约

本仓库只包含宿主侧 runner。被评测的 agent 本体、非交互评测入口 `acn_eval` 与 evaluation profile 在
ACN 仓库 [agent-claim-network](https://github.com/FTShare-Lab/agent-claim-network) 中实现。本文说明
两侧的边界、二进制的构建方式，以及双方固定的 JSON 契约。

## 1. 版本锚点

| 项目 | 值 | 说明 |
| --- | --- | --- |
| ACN 评测分支 | `feature/deepswe-claim-harness` | 包含 `acn_eval`、evaluation profile 与 claim harness 改动；尚未合入 `main` |
| 本仓库剥离自 | ACN `778c06756c6afc63f45fe1d1400054fae9c9bcd4` 的 `benchmarks/deepswe/` | runner 源码与该提交一致，仅做独立仓库所需的路径绑定改动 |
| formal 产品锚点 | `acn_main_revision = 9b818d70ddfad2f7d5e1972577dd294b19481c92`，`acn_version = 0.2.5` | `run_class=formal` 要求 `acn_revision` 是该提交的后代，且其 `Cargo.toml` 版本一致 |
| claim harness 配对基线 | `ff12e50c0bb16eb114dfd8b45353f49ef4c341b6` | [claim_harness_experiment.md](claim_harness_experiment.md) 的旧版 |

启动配置里的 `acn_checkout` 指向构建 `acn_eval` 的 ACN checkout。runner 在 dry-run 与真实启动前都会
核对：该 checkout 的 `HEAD` 等于 `acn_revision`、工作树干净、`acn_main_revision` 是其祖先、锚点提交
的 `Cargo.toml` 版本等于 `acn_version`；真实启动时还会在冻结任务镜像内运行
`acn_eval --build-info-json`，要求回报的 `commit` / `version` 与配置一致。

## 2. ACN 侧文件

| 路径（ACN 仓库） | 职责 |
| --- | --- |
| `src/bin/acn_eval.rs` | 非交互单 attempt 入口；模型 key 经匿名 pipe 原位 re-exec 交接，不留在初始环境 |
| `src/evaluation/mod.rs` | 读取 attempt TOML，构造隔离 runtime 中的单个 session，写出 `events.jsonl` 与 `result.json` |
| `src/evaluation/bundle_router.rs` | 冻结 claim bundle 的只读 router；按臂执行 Disabled / OnDemandOnce / ForcedOnce 交付策略并记录 `RouterEvidence` |
| `src/api/evaluation_usage.rs` | 仅评测模式启用的 provider usage 记录（turn / finalize 分相） |
| `src/bootstrap.rs::build_evaluation_session_engine` | 评测 SessionEngine 装配：关闭 memory、inbox、maintainer，按 `harness_mode` 选择工具面 |
| `src/config.rs::load_for_evaluation` / `activate_evaluation_runtime` | 评测配置加载与 runtime 根绑定 |
| `src/tool/registry.rs::for_*_evaluation` | evaluation tool profile 与 `submit_task` 注册 |
| `src/api/turn_loop.rs` | `submit_task` 必须是响应中的唯一工具调用；成功后立即结束 turn loop |
| `prompts/evaluation_agent_system.j2` / `prompts/evaluation_minimal_agent_system.j2` | standard 与精简 harness 的 system prompt |
| `tests/acn_eval.rs` | Rust 侧集成测试；读取本仓库 `tests/fixtures/generated-acn.toml` 的同构 fixture |
| `Cargo.toml` `[[bin]] acn_eval` | 二进制声明 |

`prompts/*.j2` 由 `include_str!` 编译进二进制，因此评测 prompt 的 revision 随 `acn_revision` 冻结，
本仓库不另存副本。

## 3. 构建 Linux x86_64 `acn_eval`

DeepSWE 任务镜像是 Linux x86_64。`docker/build-acn-eval-amd64.sh` 在宿主 Docker daemon 的原生架构上
起 builder 容器交叉编译，支持 Darwin / Linux 的 arm64 与 x86_64 宿主：

```sh
sh docker/build-acn-eval-amd64.sh --acn-checkout /absolute/path/to/agent-claim-network
```

脚本读取宿主 kernel 与 CPU 架构，从 Docker daemon 获取实际容器架构并选择原生 builder；最终产物固定为
Linux x86_64 ELF，写到 `<acn_checkout>/target/deepswe-linux-amd64/release/acn_eval`，并打印
SHA-256。缺少 Docker、平台不受支持或产物架构不符时直接失败。默认直连 Docker Hub 拉取
`ubuntu:24.04`（Pier Squid builder）与 `debian:bookworm-slim`；受限网络可用 `--mirror-prefix` 或
`ACN_DOCKER_MIRROR_PREFIX` 指定镜像源前缀，脚本会校验平台后重新打回官方 tag。

构建注入 `ACN_GIT_COMMIT` / `ACN_GIT_COMMIT_TIMESTAMP`；ACN 的 release 构建拒绝脏工作树，因此
`acn_checkout` 必须干净。

## 4. `acn_eval` 命令行

```
acn_eval --config <absolute attempt.toml>
acn_eval --build-info-json      # 打印 {"version", "commit", "commit_timestamp"}
```

只支持 Unix；模型 key 交接依赖 Linux `PR_SET_DUMPABLE`。启动顺序：

1. 若环境含 `ACN_EVAL_MODEL_KEY` 而无 `ACN_EVAL_MODEL_KEY_FD`，把 key 写入匿名 pipe，清除该变量后
   以相同参数 re-exec 自身，只传递 pipe fd 编号；
2. re-exec 后的进程从 fd 读回 key（上限 512 字节，必须是 pipe），关闭进程 dump 权限，再把 key 设为
   `ACN_EVAL_MODEL_KEY` 供 `[agent.llm].api_key_env` 读取；
3. 读取 attempt TOML，运行 attempt，最后向 stdout 打印 `result.json` 路径。`exit_type != completed`
   时以非零退出。

## 5. 容器内布局

宿主通过 Pier adapter 上传以下产物；attempt TOML 里的路径固定为容器路径：

| 容器路径 | 内容 |
| --- | --- |
| `/opt/acn-eval/acn_eval` | Linux 二进制 |
| `/opt/acn-eval/attempt.toml` | attempt 配置 |
| `/opt/acn-eval/acn.toml` | 评测生成的 ACN 配置（见 `tests/fixtures/generated-acn.toml`） |
| `/opt/acn-eval/claims.json` | 冻结 claim bundle；仅 `B_claim` / `B_forced_claim` 存在 |
| `/logs/agent/runtime/skills/coding-benchmark` | 冻结 skill |
| `/app` | 任务工作区（`workspace_root`） |
| `/logs/agent/runtime` | 全新 `acn_home`（`runtime_root`） |
| `/logs/agent/evaluation` | `events.jsonl` 与 `result.json`（`output_dir`） |

## 6. attempt TOML

`EvaluationAttemptConfig` 使用 `deny_unknown_fields`，字段如下：

| 字段 | 取值 | 说明 |
| --- | --- | --- |
| `schema_version` | `1` | 契约版本 |
| `attempt_id` | 非空字符串 | 与宿主 attempt manifest 一致 |
| `task_prompt` | 非空字符串 | 来自 normalized task 的 `instruction.md`；`B_forced_claim` 由 Rust 侧在首轮追加 `<frozen-claims>` 块 |
| `workspace_root` / `runtime_root` / `acn_config` / `output_dir` | 绝对路径 | 见上表 |
| `upstream` | `"eval"` | ACN 配置中的 upstream 名 |
| `variant` | `A` / `B_empty` / `B_claim` / `B_forced_claim` | 前两者不得设置 `claim_bundle`，后两者必须设置 |
| `attempt_deadline_secs` | 正整数 | 早于 Pier 墙钟的自有截止：`agent_seconds − deadline_reserve_seconds` |
| `model_egress_mode` | `pier` / `direct` | 冻结的模型出口模式；formal 只接受 `pier` |
| `harness_mode` | `standard`（默认）/ `minimal` / `concise` / `pi_like` / `open_code_like` | 工具面与 system prompt 变体；非 standard 只用于机制对照 |
| `claim_bundle` | 绝对路径，可选 | `{"schema_version": 1, "claims": [...]}`，只允许 `active` claim |

## 7. 输出契约

宿主用 `src/acn_deepswe/rust_contract.py` 读取以下产物，拒绝历史字段别名；`tests/fixtures/` 保存
两侧共同维护的最小样例。

### `events.jsonl`

每行一个对象：`schema_version`、`attempt_id`、`seq`（同 attempt 内严格递增且不重复）、`event_type`、
`timestamp_utc`、`payload`。当前事件类型：

| `event_type` | 含义 |
| --- | --- |
| `attempt_started` / `attempt_finished` / `attempt_failed` | attempt 生命周期；失败 payload 带 `stage=` 前缀错误摘要 |
| `forced_claim_context` | `B_forced_claim` 注入首轮上下文的 claim id |
| `model_request` | 每次 provider 请求的 usage 记录（含 phase、是否完整、模型名） |
| `evaluation_completion` | `mode=explicit_submit_task` 或 `implicit_assistant_done` |
| `evaluation_submitted` | 模型调用了 `submit_task` |
| `claim_snapshot` | finalize 后本 attempt 的 claim 快照，供宿主 freeze |
| `finalize_completed` / `session_error` | session finalize 结果与错误 |

### `result.json`

| 字段 | 说明 |
| --- | --- |
| `schema_version` | `1` |
| `attempt_id`、`exit_type` | `exit_type=completed` 才视为 agent 正常完成 |
| `agent_steps` | 模型响应次数（含 finalize） |
| `claim_new_ids` / `claim_updated_ids` / `claim_used_ids` | finalize 报告的 claim 归因 |
| `router_evidence[]` | `evidence_id`、`attempt_id`、`bundle_hash`、`query_hash`、`candidate_claim_ids`、`selected_claim_ids`、`injected_claim_ids`、`injected_content_hashes`、`timestamp_utc` |
| `router_evidence_incomplete` | router 证据记录是否受损；为 true 时 Gate 失败 |
| `usage` | `model_requests`、`turn_model_requests`、`finalize_model_requests`、`complete_model_responses`、`incomplete_model_responses`、`audit_incomplete`、`response_models[]`、`input_tokens`、`output_tokens`、`cache_read_tokens`、`reasoning_tokens`；宿主校验两组分项之和等于 `model_requests` |
| `event_ledger_path` | `events.jsonl` 绝对路径 |
| `failure_kind` | 可选；目前只有 `upstream_concurrency_exhausted`，宿主记为基础设施失败 |
| `error` | 可选；失败时带 `stage=` 前缀的摘要，成功为缺省 |

### 冻结 claim bundle 的交付策略

| 臂 | 策略 | 行为 |
| --- | --- | --- |
| `A` / `B_empty` | Disabled | router 不返回任何 claim；出现 candidate / injected / used 即 Gate 失败 |
| `B_claim` | OnDemandOnce | system context 一次展示 scope overview 与有界摘要目录；模型可执行一次 `consult_router` query 取回同 scope 的完整候选 |
| `B_forced_claim` | ForcedOnce | harness 一次性把完整 bundle 放入首轮任务上下文，模型侧查询被禁用 |

三种策略都只产生至多一条 `RouterEvidence`；Gate 据此检查候选 ⊇ 选中 ⊇ 注入 ⊇ 使用，且注入内容 hash
与冻结 bundle 一致。

## 8. 修改契约时

- Rust 侧字段、事件类型或 bundle schema 变化，必须同步更新 `rust_contract.py`、`schemas.py`、
  `gate.py` 与 `tests/fixtures/`，并在本文登记；不做历史别名兼容，`schema_version` 变化即拒绝。
- 生成的 `acn.toml` 结构变化时同步更新 `tests/fixtures/generated-acn.toml`；ACN 侧
  `tests/acn_eval.rs` 以同构 fixture 验证该配置能被 `Config::load_for_evaluation` 加载。
- 新旧计量契约的运行产物不能直接混算。
