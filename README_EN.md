# ACN DeepSWE Evaluation

[中文评测报告](README.md) · [Chinese runner](docs/runner.md)

This repository is the auditable evaluation runner for
[Agent Claim Network (ACN)](https://github.com/FTShare-Lab/agent-claim-network) on
[DeepSWE](https://deepswe.datacurve.ai/). On frozen DeepSWE / Pier revisions it runs four ACN arms per
task, grades them with the official DeepSWE program verifiers, and turns every step of task freezing,
model access, claim isolation, usage accounting and result attribution into reproducible evidence.

DeepSWE v1.1 is maintained by [Datacurve](https://github.com/datacurve-ai/deep-swe): 113 long-horizon
software engineering tasks written from scratch against active open-source repositories, spanning 91
repositories and 5 languages. Each task runs in an isolated container and is graded by a hand-written,
behaviour-level verifier; the official leaderboard runs every model through
[Pier](https://github.com/datacurve-ai/pier) with mini-swe-agent. This runner reuses Pier's task format,
container isolation, network allowlist and verifier, and only swaps the agent for ACN.

The evaluation answers two questions: where ACN without claims lands on DeepSWE in pass rate, tokens and
agent steps; and whether, on the same model and the same tasks, a second fresh agent that receives the
claims frozen from a previous agent through the router outperforms a fresh agent without claims. The
methodology is in [docs/methodology.md](docs/methodology.md) (Chinese); results are in
[README.md](README.md).

## Four arms

For every task the runner first executes `A` and `B_empty`. Once `A` finishes, the host writes an
immutable freeze barrier and freezes the claim bundle; the two claim-consuming B arms then start from a
pristine workspace:

| Arm | Role | How claims reach the model |
| --- | --- | --- |
| `A` | producer; solves independently and yields claims that can be frozen | no prior claims |
| `B_empty` | same-task baseline without claims | no claims at all |
| `B_claim` | the real end-to-end path with autonomous retrieval | the frozen router is available and the system context shows a bounded summary catalog; whether to call `consult_router` for the full text is up to the model |
| `B_forced_claim` | controlled comparison | the harness queries the frozen router for the bundle and appends the same claims to the first-turn task context |

The primary comparison is the per-task paired difference of `B_claim` and `B_forced_claim` against
`B_empty`. B arms never see A's patch, workspace, session, logs or private memory; apart from the claim
delivery mode, all four arms share the same system prompt, skill, tools, budgets and verifier. The default
`claim_quality_gate=verified_producer_only` quarantines all claims from a producer that failed the
verifier: the two claim arms then receive an empty bundle recorded as `EMPTY_CLAIM_BUNDLE`, and claims
are never fabricated or borrowed from another task.

## Relation to the official setup

- **Model access** follows Pier's official adapters; there is no custom proxy or broker. The model key
  is read from the host variable `ACN_EVAL_UPSTREAM_KEY` and handed to `acn_eval` only as the container
  variable `ACN_EVAL_MODEL_KEY`; the process re-execs itself through an anonymous pipe to scrub its
  initial environment, so the key never reaches argv, config files, manifests or JSONL.
- **Egress** is pinned by Pier's Squid domain allowlist to the host name of `ACN_EVAL_UPSTREAM_BASE_URL`;
  both agent and verifier run with `allow_internet = false`, and `code_run` subprocesses drop the key
  variable. `model_egress_mode` is part of the frozen launch config; `"pier"` is the default and the only
  value admissible for formal results, while `"direct"` is for connectivity diagnostics, is recorded in
  the manifest and fails the formal Gate.
- **Usage** is accumulated by `acn_eval` from upstream `usage` fields into `result.json`; the host adds
  `cache_hit_rate`. Reasoning tokens count against `max_tokens`; the official mini-swe-agent sets no
  output cap, this runner defaults to 65536.
- **Completion semantics**: the evaluation profile exposes a no-argument `submit_task` that the model
  should call as the only tool call once implementation, tests and diff review are done. After it, no
  further model request is made; session finalize and the Pier verifier follow. A consumable final
  reply that omits the call is recorded as `implicit_assistant_done` and takes the same path;
  truncation, errors, unconsumable output and deadlines remain agent failures.
- **Resources and timeouts**: the official-aligned group uses 2 CPU / 8 GiB / 20 GiB, a 5400 s agent
  timeout and a 1800 s verifier timeout; ACN reserves 120 s before the deadline for finalize. Any
  extended budget can only be labelled diagnostic.

The four arms are not a replica of the official single-agent leaderboard; runner results must not be
placed on the same scoreboard as externally published numbers.

## Layout

```
src/acn_deepswe/        runner (standard library only; datacurve-pier is an optional runtime dependency)
  dataset.py            task freezing and tree hashes
  network.py            fail-closed DeepSWE network_mode → Pier allow_internet translation
  plan.py               deterministic attempt plans
  provenance.py         immutable provenance and the directory tree hash algorithm
  pier_adapter.py       Pier BaseAgent adapter: uploads, allowlist, model egress, single-attempt run
  host_runner.py        per-task orchestration: producer wave → freeze → consumer wave
  claim_freeze.py       claim bundle freezing on freeze barriers
  gate.py               machine-checkable infrastructure / attribution / isolation gate
  rust_contract.py      strict parser for acn_eval artifacts (result.json / events.jsonl)
  presmoke.py           multi-task scheduling and aggregate (pairing, strata, claim funnel)
  presmoke_cli.py       acn-deepswe-presmoke: launch from a frozen manifest, dry-run, resume
  auto_run.py           acn-deepswe-auto: prepare / run / monitor
  cli.py                acn-deepswe: freeze / plan / validate-config audit commands
  resource_guard.py     Docker-wide mutex, capacity admission and stale-resource cleanup
tests/                  unittest suite and Rust contract fixtures
manifests/              example launch configs (*.example.json) and historical frozen manifests
assets/coding-benchmark the frozen skill injected into all four arms
docker/                 builder that cross-compiles the Linux x86_64 acn_eval
docs/                   methodology, run guides, contracts and results
```

## Quick start

### Prerequisites

- Python 3.12+ and a Docker daemon (Linux amd64 or arm64 hosts, macOS Docker Desktop included).
- A DeepSWE checkout and a Pier checkout, both at the frozen revision with clean worktrees. Pier must be
  installed editable into its own venv: `pier_executable` is that venv's `bin/pier`, and its PEP 610
  `direct_url` must point at the frozen Pier checkout.
- An ACN checkout, the source `acn_eval` is built from (see
  [docs/acn_integration.md](docs/acn_integration.md)).

### Install the runner

```sh
git clone https://github.com/FTShare-Lab/acn-deepswe-eval
cd acn-deepswe-eval
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -e .
PYTHONPATH=src .venv/bin/python -m unittest discover -s tests -p 'test_*.py'
```

### Build the Linux `acn_eval`

```sh
sh docker/build-acn-eval-amd64.sh --acn-checkout /absolute/path/to/agent-claim-network
```

The artifact is a Linux x86_64 ELF at `<acn_checkout>/target/deepswe-linux-amd64/release/acn_eval`.

### Freeze tasks

```sh
acn-deepswe validate-config /absolute/DeepSWE/tasks/<task> /absolute/checked
acn-deepswe freeze-execution-dataset /absolute/DeepSWE/tasks \
  /absolute/runs/current/frozen-manifest.json /absolute/runs/current/normalized \
  --deepswe-checkout /absolute/DeepSWE --pier-checkout /absolute/pier \
  --seed 17 --sample-size 30
acn-deepswe plan /absolute/runs/current/frozen-manifest.json /absolute/runs/current --seed 99
```

`validate-config` performs the fail-closed network translation: a Pier-compatible copy is generated only
when both `agent.network_mode` and `verifier.network_mode` are `"no-network"`, writing
`allow_internet = false` for both environments and preserving `[[verifier.collect]]`; source and result
SHA-256 are printed together. `freeze-execution-dataset` verifies the exact revisions and clean worktrees
of both checkouts before writing, generates offline task copies in bulk, and freezes each task's TOML and
directory tree hashes; it refuses to overwrite an existing manifest or normalized directory. Use
`--sample-size 5` for Pre-smoke, `30` for Smoke and `113` for the full set; sampling is always a
stable-sorted, fixed-seed selection without replacement. `plan` derives the four-arm attempt plan.

### Launch config and dry-run

Copy [manifests/presmoke-run.example.json](manifests/presmoke-run.example.json) to an absolute path
outside the repository and fill in both checkouts, `acn_checkout`, the Linux `acn_eval`, this
repository's `assets/coding-benchmark`, the frozen model names and the resource budget. **The config must
not contain credentials**; they are read from the host environment only. `frozen-model-alias` /
`frozen-model-checkpoint` in the example are placeholders.

```sh
ACN_EVAL_UPSTREAM_BASE_URL=<https-url> \
acn-deepswe-presmoke --config /absolute/path/to/presmoke-run.json --dry-run
```

The dry-run statically verifies both checkout revisions, the binding between `acn_checkout` and
`acn_revision`, the source/normalized task tree hashes and the complete four-arm plan. It executes no
Linux binary and does not touch Docker.

### Real execution

```sh
ACN_EVAL_UPSTREAM_BASE_URL=<https-url> ACN_EVAL_UPSTREAM_KEY=<key> \
acn-deepswe-presmoke --config /absolute/path/to/presmoke-run.json
```

Use `--read-key-stdin` to enter the key without leaving it in shell history; it is read only for real
execution when the variable is absent and is cleared on exit. Before any attempt directory is created,
the runner checks the Pier executable / checkout binding, `pier --help`, the Docker daemon, that every
task image resolves to a local content digest, that the Pier egress proxy image digest matches, and that
Docker's `NCPU` / `MemTotal` can hold `task_workers × cpus` and `task_workers × memory_mb`. Insufficient
capacity fails hard; concurrency is never reduced silently.

After preflight the runner copies `acn_deepswe`, the Pier package, its console script, the coding skill
and `acn_eval` once into a read-only `output_dir/frozen-python/`; all arms import from there, and every
arm re-verifies the binary, skill, task and both Python source tree hashes. Tasks run in a producer wave
and a consumer wave with intra-wave parallelism; all tasks and arms share `task_workers` attempt permits,
and Pier trials use `max_retries=0`. Infrastructure or Gate failures exit non-zero and never retry a
solve automatically.

Pier is pinned to `force_build=false` (the frozen `task.toml` image), `delete=false` (compose containers
are torn down after a trial while local images are kept), `n_attempts=1` and `n_concurrent_trials=1`.

### Automation and monitoring

Smoke-then-full runs, direct full runs, the two-stage A-then-B flow, adaptive producer selection and
read-only monitoring live in `acn-deepswe-auto`; see [docs/automated_run.md](docs/automated_run.md) and
[docs/solver_aligned_run.md](docs/solver_aligned_run.md). The paired experiment between two ACN
revisions is described in [docs/claim_harness_experiment.md](docs/claim_harness_experiment.md).

## Launch config reference

Fields accepted by `acn-deepswe-presmoke` (anything else is rejected):

| Field | Meaning |
| --- | --- |
| `frozen_manifest` / `attempt_plan` / `normalized_root` / `output_dir` | frozen manifest, attempt plan, offline task copies and host output directory; absolute paths |
| `deepswe_checkout` / `source_tasks_root` / `pier_checkout` / `pier_executable` | frozen DeepSWE checkout, task root, Pier checkout and its venv `bin/pier` |
| `acn_checkout` / `acn_eval` | the ACN checkout `acn_eval` was built from (HEAD must equal `acn_revision` and be clean) and the Linux binary |
| `acn_revision` / `acn_main_revision` / `acn_version` | evaluated commit, product baseline commit and version; `formal` is pinned to `9b818d70…` / `0.2.5` |
| `frozen_skill` | complete skill directory containing `SKILL.md`; identical for all arms, hash recorded |
| `pier_egress_proxy_image` / `pier_egress_proxy_content_digest` | Pier Squid proxy image and content digest; `formal` requires `pier-egress-proxy:ubuntu-24.04` |
| `model` / `response_model` / `reasoning_effort` | request model name, checkpoint echoed by the upstream, reasoning effort |
| `run_class` | `formal` or `diagnostic` |
| `model_egress_mode` | `pier` (formal) or `direct` (diagnostic) |
| `harness_mode` | `standard` (default), `minimal`, `concise`, `pi_like`, `open_code_like`; non-standard modes are for mechanism comparisons only |
| `claim_quality_gate` | `verified_producer_only` (default) or `none` |
| `file_edit_authority_enabled` | whether ACN's file-edit authority check is enabled |
| `resources` | `cpus`, `memory_mb`, `storage_mb`, `max_tokens`, `context_window` |
| `timeouts` | `agent_seconds`, `deadline_reserve_seconds`, `verifier_seconds`; `agent_seconds` drives the Pier wall clock, the ACN request timeout and the attempt deadline |
| `llm_retry` | `retry_count`, `retry_base_delay_ms`, `retry_max_delay_ms` |
| `progress` | `poll_secs` (default 30), `stall_after_secs` (default 600); marks suspected stalls, never terminates |
| `host_capacity` | `memory_reserve_mb`, `disk_reserve_mb`, `disk_admission_mb_per_worker` (`formal` requires at least 8192) |
| `task_workers` | global attempt permits, default 1 |
| `cleanup_stale_pier_resources` | before starting, remove stopped containers with Pier Compose evidence and the images they produced, and verify the egress proxy image digest |
| `run_all_variants_without_claims` | run both claim arms with an empty bundle when no claim is eligible |
| `run_a_only` / `b_only_from_a_output_dir` | two-stage A-then-B continuation |
| `claim_producer_variant` / `producer_pair_only` / `adaptive_source_output_dir` / `producer_selection_manifest` | `A` (default) or the two-stage `adaptive` producer selection |

`acn-deepswe-auto` replaces the generated manifest / plan / output paths and `acn_revision` with
`run_root`, `smoke_size`, `full_size`, `dataset_seed`, `smoke_plan_seed`, `full_plan_seed`,
`adaptive_producer_selection` and `reuse_local_agent_image_fingerprint`.

## Artifacts

Each attempt's `output_path` holds `host-config/` (attempt TOML, ACN config, Pier job and trial),
`gate.json`, `attempt-result.json` and `progress.json`. Under the Pier trial,
`agent/evaluation/{result.json,events.jsonl}`, `artifacts/model.patch` and the pinned `TrialResult` are
referenced and parsed. The attempt TOML pins `workspace_root=/app`, `runtime_root=/logs/agent/runtime`,
`output_dir=/logs/agent/evaluation` and `acn_config=/opt/acn-eval/acn.toml`; `B_claim` and
`B_forced_claim` add `claim_bundle=/opt/acn-eval/claims.json`.

`attempt-result.json` records `status`, `verifier_passed`, `agent_steps`, `usage`, `gate`, `pier_trial`,
`verifier_regrade`, `failure_kind` and the `stage=`-prefixed `agent_error`. `verifier_passed` is true
only when the agent completed normally and the verifier passed. When the Rust result carries
`failure_kind=upstream_concurrency_exhausted` (HTTP 429 with an explicit capacity-exhausted code), the
host records an infrastructure failure, keeps the evidence, and skips Gate, freeze and the B arms.

`progress.json` is written atomically every `poll_secs` with the session event path, event count, last
activity time and last event type; `stall_after_secs` without events marks `possibly_stalled` as a hint
for human inspection only. Operator interrupts are recorded as `INTERRUPTED_BY_OPERATOR`.

`output_dir/presmoke-aggregate.json` summarises all tasks: `cohort_coverage` (planned / included /
excluded with reasons, denominator fixed to the frozen task set), `cohort_metrics` stratified by producer
outcome (per-arm passes, usage sums / means, `empty_claim_bundle_attempts`), the two paired comparisons
`paired_against_producer` and `paired_against_no_claim_baseline` (wins / losses and the two-sided exact
binomial `exact_mcnemar_p`), and `claim_funnel` (per arm: bundle available, router retrieved, content
injected, model-reported use, with claim counts). Per-task manifests, jobs and claim bundles live in
`output_dir/tasks/<task>/`; `task-completions.json` persists every terminal task state.

## What the Gate checks

The Gate verifies infrastructure, claim attribution and isolation only: artifact hash, that the verifier
actually ran, complete usage reporting, that echoed model names equal `response_model`, Pier task
checksum / trial isolation, that `B_empty` never sees a claim, and that the claim arms only use claims
from the frozen bundle (candidates ⊇ selected ⊇ injected ⊇ used, content hashes matching).

**A verifier score of 0 and an agent-side failure are valid experimental results, not Gate failures**;
they count as not passed and must never be rerun for a better score. The checkpoint persists all
terminal states; a plain `--resume` refuses any failed terminal state. Only an interrupted task with no
terminal state and partial artifacts may be rerun once with an explicit `--resume --retry-interrupted`,
keeping prior artifacts and retry counts.

## Results

See [README.md](README.md).

## Documentation

All documents are in Chinese.

- [docs/methodology.md](docs/methodology.md): dataset, official setup, ACN alignment, the four-arm
  visibility matrix, strata and metric definitions
- [docs/acn_integration.md](docs/acn_integration.md): ACN-side files, building and invoking `acn_eval`,
  the attempt TOML and the `result.json` / `events.jsonl` contract
- [docs/automated_run.md](docs/automated_run.md): Smoke → Full automation, two-stage continuation,
  resume and monitoring
- [docs/solver_aligned_run.md](docs/solver_aligned_run.md): solver-aligned full run
- [docs/claim_harness_experiment.md](docs/claim_harness_experiment.md): paired experiment protocol
  between two ACN revisions
- [docs/claim_harness_design.md](docs/claim_harness_design.md): design of the evaluated claim harness
  variant
- [README.md](README.md): evaluation report (Chinese)

## Provenance

The runner was extracted from `benchmarks/deepswe/` at commit
`778c06756c6afc63f45fe1d1400054fae9c9bcd4` on the ACN branch `feature/deepswe-claim-harness`. The only
behavioural change made for the standalone repository is that the ACN checkout is no longer inferred
from the runner's own location: the launch config names it explicitly as `acn_checkout`, and the build
script takes the same path as `--acn-checkout`. The Rust `acn_eval` binary and the evaluation profile
stay in the ACN repository; see [docs/acn_integration.md](docs/acn_integration.md) for the anchors.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (Chinese).

## License

MIT OR Apache-2.0; see [LICENSE-MIT](LICENSE-MIT) and [LICENSE-APACHE](LICENSE-APACHE).
