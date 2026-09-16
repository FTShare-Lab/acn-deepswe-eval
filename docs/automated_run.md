# 自动化运行：Smoke 后补齐全量，或直接全量

`acn-deepswe-auto` 由外部调度器启动，监控方不会启动任何评测。它先冻结全部 113 题；当 `smoke_size`
大于 0 时，从中确定性抽取 Smoke，只有 Smoke 全部完成且没有 runner 或 Gate 失败时，才以相同的模型、
资源、skill 和重试配置补跑其余任务。设为 `0` 时不创建或运行 Smoke，直接执行完整冻结任务集。两种方式
都不会重复执行同一题。示例开启 `run_all_variants_without_claims`，因此每题均实际执行四臂；A 未生成
claim 时，claim 臂使用同题 freeze 后的空 bundle，并留下可汇总的空 bundle 标记。

## 配置

复制 [automated-run.example.json](../manifests/automated-run.example.json) 到仓库外的绝对路径，填写
本机的 DeepSWE / Pier checkout、构建 `acn_eval` 的 ACN checkout（`acn_checkout`）、`acn_eval` 二进制、
本仓库的 `assets/coding-benchmark` 和 run root。示例中的 `frozen-model-alias` /
`frozen-model-checkpoint` 是占位值：`model` 填发送给模型服务的请求模型名，`response_model` 填上游实际
回显的 checkpoint 名，二者都会写入 provenance 并由 Gate 核对。

配置中禁止 key。外部启动器必须在受保护的环境中提供 `ACN_EVAL_UPSTREAM_KEY` 与
`ACN_EVAL_UPSTREAM_BASE_URL`，二者都不会写入配置、manifest 或日志。

示例的 30 个 `task_workers` 配合每题 2 CPU / 16 GiB，真实执行前会要求 Docker 至少提供
`task_workers × cpus` 个 CPU 与 `task_workers × memory_mb` 的内存。资源不够会直接退出，不会降低
并发或启动部分任务。

## 命令

先执行 `prepare` 只做冻结与配置生成，不请求模型；随后由调度器执行 `run`：

```sh
export ACN_EVAL_UPSTREAM_BASE_URL=<https-url>
export ACN_EVAL_UPSTREAM_KEY=<key>
python -m acn_deepswe.auto_run --config /absolute/path/to/automated-run.json prepare
python -m acn_deepswe.auto_run --config /absolute/path/to/automated-run.json run
```

若宿主未设置模型 key，可将最后一条命令改为 `run --read-key-stdin`；自动化父进程只会在终端隐藏读取
一次，仅在自身内存中继承给所运行阶段，结束即清除。该值不会写入运行配置、manifest 或日志。若要跳过
Smoke，设置 `"smoke_size": 0`、`"full_size": 113`，`run` 会直接进入 `full` 阶段。

`prepare` 会读取 `acn_checkout` 的 `HEAD` 作为各阶段配置的 `acn_revision`，并要求该工作树干净；
真实启动时 runner 再次核对该 revision、其与 `acn_main_revision` 的祖先关系，以及冻结任务镜像内
`acn_eval --build-info-json` 回报的 commit / version。

## 分阶段：先 A，再补 B

需要先评估 A、满意后再补三条 B 臂时，使用两个独立 `run_root`。第一阶段设置
`"run_a_only": true`、`"smoke_size": 0`；每题执行 A、写入 freeze barrier 和 claim bundle，三条 B
臂以 `A_ONLY` 终态留档。第二阶段保持相同的任务 seed、plan seed、模型、effort、资源、超时、镜像、
二进制与源码，设置 `"run_a_only": false`、`"run_all_variants_without_claims": true`，并增加：

```json
"b_only_from_a_output_dir": "/absolute/path/to/a-run/full/output"
```

第二阶段只调度 `B_empty`、`B_claim`、`B_forced_claim`，不会重跑 A。真实执行前会先校验全部 task 的
A-only manifest、Gate、freeze barrier、claim bundle、task checksum 与公平性 provenance；任一 task
缺失、被修改或配置漂移时，整批 B 在创建 attempt 目录前失败。B manifest 同时保留来源 A 的证据路径和
source manifest hash。B-only 必须设置 `smoke_size=0`，且不能与 `run_a_only` 同时启用。

## 续跑与互斥

`run` 会继承原有 key，但不打印、不写入配置、manifest 或命令行。同一 `run_root` 有跨进程锁，第二个
自动编排器会被拒绝，不能并行覆盖 checkpoint。若进程中断，普通 `run` 只报告阶段需要人工确认，不会自动
续跑。操作者确认是无终态的中断后，显式传 `run --resume-interrupted`，它才向阶段传递
`--resume --retry-interrupted`；每个 task 只允许一次。`task-completions.json` 会持久化所有 task
终态，Gate / 协议 / 基础设施失败均不可由该路径重跑。四臂完整且 Gate 通过的 task 会复用；授权的中断
task 在 `output/resumes/resume-XXX/` 重新执行，旧半成品不会被覆盖。有 Smoke 的配置在 Smoke 完整后才
启动后续任务。

## 只读监控

监控端只运行以下只读命令。它汇总各阶段、所有 `progress.json` 状态、疑似停滞条目及过期的 active
快照；后者表示运行进程可能已退出，不能将历史 `active` 当作仍在运行。该命令不创建、启动、终止或重试
任务：

```sh
python -m acn_deepswe.auto_run --config /absolute/path/to/automated-run.json monitor
```
