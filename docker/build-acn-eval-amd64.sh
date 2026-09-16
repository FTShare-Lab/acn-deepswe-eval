#!/usr/bin/env sh
# 在宿主 Docker daemon 的原生架构上构建 DeepSWE 评测所需的 Linux x86_64 `acn_eval`。
# 评测 runner 与 ACN 源码分属两个仓库：ACN checkout 由 --acn-checkout 或 ACN_CHECKOUT 指定，
# 产物写入该 checkout 的 target/deepswe-linux-amd64/release/acn_eval。
set -eu

usage() {
  printf '用法：%s --acn-checkout <ACN 仓库绝对路径> [--mirror-prefix PREFIX]\n' "$0" >&2
  printf '  --acn-checkout   干净的 agent-claim-network checkout；也可用环境变量 ACN_CHECKOUT\n' >&2
  printf '  --mirror-prefix  可选的基础镜像源前缀（默认直连 Docker Hub）；也可用 ACN_DOCKER_MIRROR_PREFIX\n' >&2
}

acn_checkout=${ACN_CHECKOUT:-}
mirror_prefix=${ACN_DOCKER_MIRROR_PREFIX:-}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --acn-checkout)
      [ "$#" -ge 2 ] && [ -n "$2" ] || {
        usage
        exit 2
      }
      acn_checkout=$2
      shift 2
      ;;
    --mirror-prefix)
      [ "$#" -ge 2 ] && [ -n "$2" ] || {
        usage
        exit 2
      }
      mirror_prefix=${2%/}
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$acn_checkout" in
  /*) ;;
  *)
    printf '错误：--acn-checkout 必须是绝对路径（当前：%s）\n' "${acn_checkout:-<空>}" >&2
    usage
    exit 2
    ;;
esac
[ -f "$acn_checkout/Cargo.toml" ] && [ -f "$acn_checkout/src/bin/acn_eval.rs" ] || {
  printf '错误：%s 不是包含 src/bin/acn_eval.rs 的 ACN checkout\n' "$acn_checkout" >&2
  exit 1
}

host_os=$(uname -s)
host_arch=$(uname -m)
host_kernel=$(uname -r)

case "$host_os/$host_arch" in
  Darwin/arm64 | Darwin/x86_64 | Linux/arm64 | Linux/aarch64 | Linux/x86_64) ;;
  *)
    printf '错误：不支持的宿主平台：%s/%s\n' "$host_os" "$host_arch" >&2
    exit 1
    ;;
esac

if ! docker_info=$(docker info --format '{{.OSType}}/{{.Architecture}}'); then
  printf '错误：无法连接 Docker daemon\n' >&2
  exit 1
fi
case "$docker_info" in
  linux/arm64 | linux/aarch64) builder_platform=linux/arm64 ;;
  linux/amd64 | linux/x86_64) builder_platform=linux/amd64 ;;
  *)
    printf '错误：不支持的 Docker daemon 平台：%s\n' "$docker_info" >&2
    exit 1
    ;;
esac

pull_base_image() {
  official_image=$1
  if [ -n "$mirror_prefix" ]; then
    source_image="$mirror_prefix/$official_image"
  else
    source_image=$official_image
  fi

  docker pull --platform "$builder_platform" "$source_image"
  if [ "$source_image" != "$official_image" ]; then
    docker tag "$source_image" "$official_image"
  fi
  image_platform=$(docker image inspect "$official_image" --format '{{.Os}}/{{.Architecture}}')
  [ "$image_platform" = "$builder_platform" ] || {
    printf '错误：镜像 %s 平台为 %s，预期 %s\n' \
      "$official_image" "$image_platform" "$builder_platform" >&2
    exit 1
  }
  docker image inspect "$official_image" --format '{{.RepoTags}} {{.Os}}/{{.Architecture}} {{.Id}}'
}

if [ -n "$mirror_prefix" ]; then
  debian_base_image="$mirror_prefix/debian:bookworm-slim"
else
  debian_base_image=debian:bookworm-slim
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
image_name=${ACN_EVAL_BUILDER_IMAGE:-acn-eval-amd64-builder:rust-1.90}
output_dir="$acn_checkout/target/deepswe-linux-amd64"
binary_path="$output_dir/release/acn_eval"
git_commit=$(git -C "$acn_checkout" rev-parse HEAD)
git_commit_timestamp=$(git -C "$acn_checkout" show -s --date=format:%Y-%m-%d\ %H:%M:%S --format=%cd HEAD)

printf '构建环境：host=%s/%s kernel=%s docker=%s builder=%s target=linux/amd64 acn=%s@%s\n' \
  "$host_os" "$host_arch" "$host_kernel" "$docker_info" "$builder_platform" "$acn_checkout" "$git_commit"

# ubuntu:24.04 供 Pier 的 Squid egress proxy builder 使用，与 acn_eval 的 debian builder 一并预拉取并校验平台。
pull_base_image ubuntu:24.04
pull_base_image debian:bookworm-slim

docker build --platform "$builder_platform" \
  --build-arg "BASE_IMAGE=$debian_base_image" \
  -f "$script_dir/acn-eval-amd64-builder.Dockerfile" \
  -t "$image_name" \
  "$script_dir"
mkdir -p "$output_dir/release"
docker run --platform "$builder_platform" --rm -v "$acn_checkout:/work" -w /work \
  -e "ACN_GIT_COMMIT=$git_commit" \
  -e "ACN_GIT_COMMIT_TIMESTAMP=$git_commit_timestamp" \
  "$image_name" \
  cargo build --release --target x86_64-unknown-linux-gnu --bin acn_eval
cp "$acn_checkout/target/x86_64-unknown-linux-gnu/release/acn_eval" "$binary_path"

binary_info=$(file "$binary_path")
printf '%s\n' "$binary_info"
case "$binary_info" in
  *"ELF 64-bit"*"x86-64"*) ;;
  *)
    printf '错误：构建产物不是预期的 Linux x86_64 ELF：%s\n' "$binary_path" >&2
    exit 1
    ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$binary_path"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$binary_path"
else
  printf '错误：缺少 SHA-256 工具（需要 sha256sum 或 shasum）\n' >&2
  exit 1
fi
