# 参与贡献

本仓库是 ACN 在 DeepSWE 上的评测 runner。ACN 产品本体、`acn_eval` 二进制与 evaluation profile 位于
[agent-claim-network](https://github.com/FTShare-Lab/agent-claim-network)；改动 Rust 侧契约请在该仓库
提交，并在本仓库同步更新 [docs/acn_integration.md](docs/acn_integration.md) 与 `tests/fixtures/`。

## 开发环境

runner 只依赖 Python 3.12+ 标准库；`datacurve-pier` 是真实执行时才需要的 optional dependency。

```sh
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -e . ruff
PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_*.py'
.venv/bin/ruff check .
```

提交前请保证单元测试与 `ruff check` 通过，示例 manifest 能被 `load_config` 读取（`tests/test_example_manifests.py`）。
真实评测不在开发机上运行；涉及 Docker、Pier 或模型请求的行为改动请在 PR 中说明在评测机上做过的验证。

## 公开仓库边界

- 任何位置都不得出现明文密钥、真实 endpoint、内网域名或内部主机路径。示例路径统一写
  `/absolute/path/to/...` 一类中性占位符；域名使用 `.example` / `.invalid` 等保留域名。
- 示例与 fixture 中的模型名使用 `frozen-model-alias` / `frozen-model-checkpoint` 一类占位值，不写
  任何真实部署的路由别名。
- 配置文件不承载 credential；模型 key 与 base URL 只从 `ACN_EVAL_UPSTREAM_KEY` /
  `ACN_EVAL_UPSTREAM_BASE_URL` 环境变量读取，runner 会拒绝包含 key 字段的配置。
- 评测结果只在 [README.md](README.md) 发布，且必须附带可重建的 provenance；不得把
  单次、未过 Gate 或未冻结出口模式的运行写成正式分数。
- 任务源码、容器日志与模型输出不进入仓库。

## 代码约定

- 外部产物（Pier `TrialResult`、Rust `result.json` / `events.jsonl`、DeepSWE `task.toml`）在读取边界
  校验并以 `ValueError` 子类暴露无效数据；内部已建模的数据不重复校验。
- 不为单一调用点增加 wrapper、fallback 或兼容分支；正式门禁不得静默放宽资源、并发或隔离约束。
- 报错信息带定位锚点（task id、attempt id、路径、阶段名），不抛裸异常。
- 模块顶部用简短中文说明职责；注释解释约束与原因，不复述代码。

## 提交信息

沿用 `[feat] / [fix] / [docs] / [test] / [chore] / [ci]: 中文摘要` 的格式，正文按点列出改动与原因。
