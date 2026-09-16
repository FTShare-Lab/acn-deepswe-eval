# 结果

> 状态：待更新。

本页只发布满足下列条件的运行：`run_class=formal` 或明确标注的 `diagnostic`，全部 task-arm 的 Gate、
provenance、attempt result 与 aggregate 可被重建，且模型出口模式已写入冻结 attempt 配置。此前的
诊断性运行没有把模型出口模式写入 attempt 配置，不能在当前 Gate 下被重新认证为正式得分，因此不在
此处列出；在同一冻结任务、模型与资源设置下重新运行后再更新。

## 将报告的内容

每次发布包含以下部分，数字均以完整冻结 task 集为分母：

1. **冻结配置**：DeepSWE / Pier revision、ACN `acn_revision` 与 `acn_main_revision`、runner 源码
   tree hash、skill hash、请求模型名与响应 checkpoint、`reasoning_effort`、资源、超时、重试、模型出口
   模式、`claim_quality_gate`、producer 选择方式与 rollout 数。
2. **覆盖**：每臂计划 / 实际 / 计分 attempt 数；基础设施失败、Gate 失败、空 bundle、被隔离 producer 与
   缺失 arm 按原因计数（`cohort_coverage`）。
3. **成功率**：每臂 verifier 通过数 / 113；按 producer 结果分层（`success_efficiency`、
   `failed_producer_quarantine`、`unpaired_no_claim`）。
4. **配对比较**：`B_claim − B_empty`、`B_forced_claim − B_empty` 与 consumer − producer 的同题配对，
   给出均通过 / 仅 reference 通过 / 仅 subject 通过 / 均失败四格、净变化与双侧精确 McNemar p 值；多
   rollout 时同时给逐 rollout 结果与按 task 聚类的不确定性。
5. **用量**：每臂 `turn_model_requests`、`finalize_model_requests`、input / output / cache-read /
   reasoning token 的总和与均值、`cache_hit_rate`、`incomplete_model_responses` 数；成功效率只比较同题
   均通过的样本。
6. **claim 使用漏斗**：bundle 可用 → router 检索 → 内容注入 → 模型报告使用，每层同时给 task 数与
   claim 数。
7. **解释边界**：与官方单 agent 榜单的口径差异、未控制的变量与不能得出的结论。

## 如何重建

保留运行的 `frozen-manifest.json`、`attempt-plan.json`、`presmoke-aggregate.json`、每题
`tasks/<task>/manifest.json` 与 `claims.json`、每臂 `attempt-result.json` / `gate.json` /
`progress.json`，以及 resume manifest。上述各项均可由这些产物按 [methodology.md](methodology.md)
第 10 节的定义重算；发布时附带产物目录的 tree hash。
