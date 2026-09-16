# 解题对齐全量运行

该轮用于观察轻量解题 harness 的两项可控改动：关闭文件修改许可证与 Memory 相关运行时路径，并在所有
ACN arms 使用相同的解题流程、非结束轮工具调用纪律和与 mini-swe-agent Responses 对照对齐的采样参数。
它仍是 ACN 四臂实验，不能与单 agent 的外部得分直接并列。

运行时生成的 ACN TOML 固定为：

- `agent.tool.file_edit_authority_enabled=false`；
- `agent.memory.enabled=false`；
- `agent.session.memory_review.enabled=false`；
- `agent.llm.temperature=1.0`；
- `agent.llm.top_p=0.95`。

请求模型名与预期响应 checkpoint 按冻结值填写 `model` / `response_model`，provider 保持
`openai_responses`，`reasoning_effort=max`，上下文能力声明为 1,000,000，输出上限为 65,536。模型凭据
和 base URL 仅从受保护的运行环境读取，不能放入本文件、JSON 配置或命令行。

## 直接全量

将 [automated-run-solver-aligned-full.example.json](../manifests/automated-run-solver-aligned-full.example.json)
复制到仓库外的私有位置，替换其中所有本机路径与模型占位值。该 profile 固定 `smoke_size=0`、
`full_size=113`、`task_workers=20` 和每题四臂，因此计划总数为 452 个 task-arm，而不是重复执行四轮
独立实验。它使用 `claim_producer_variant=adaptive` 与 `adaptive_producer_selection=true`：先完成两个
无 claim 臂，再按预注册规则选出 producer，最后运行两个 claim 消费臂。该选择依赖观测结果，属于探索性
分析，不能把被选中的基线称为未经选择的独立 baseline。

模型就绪后，先完成不请求模型的准备，再由常驻会话启动：

```sh
export ACN_EVAL_UPSTREAM_BASE_URL=<https-url>
python -m acn_deepswe.auto_run --config /absolute/path/to/automated-run.json prepare
python -m acn_deepswe.auto_run --config /absolute/path/to/automated-run.json run --read-key-stdin
```

`prepare` 会验证冻结环境、Docker 容量与四臂计划。`run --read-key-stdin` 只在终端隐藏读取凭据，不把
凭据写入 artifact；如受保护环境已注入 `ACN_EVAL_UPSTREAM_KEY`，也可省略该参数。运行后的只读监控
命令为：

```sh
python -m acn_deepswe.auto_run --config /absolute/path/to/automated-run.json monitor
```

除已确认的无终态中断外，不通过普通 `--resume` 重跑 task；需要恢复时使用既有的 `--resume-interrupted`
受限路径，以保留原始 attempt 和归档证据。

## 复用本地 agent 镜像（仅 diagnostic）

`reuse_local_agent_image_fingerprint` 允许本轮复用宿主上已有的 mini-swe-agent 任务镜像
（形如 `hb__<task>__agent-<fingerprint>`）。冻结任务会把 `docker_image` 改写为这些本地 tag，四臂只从
同一镜像起新容器，不再 build agent 层；trial 结束只拆 Compose 容器，保留镜像给后续臂复用。镜像缺失时
直接失败，禁止拉取。该选项只允许在 `run_class=diagnostic` 下使用，`formal` 运行必须使用冻结任务
指向的官方镜像。宿主磁盘使用率不得超过根分区 75%。
