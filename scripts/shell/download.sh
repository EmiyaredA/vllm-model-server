#!/usr/bin/env bash
# 模型/数据集下载脚本
#
# 用法：改下面「下载列表」，取消注释要下的那一行，然后执行：
#   bash scripts/shell/download.sh
#
# 也可临时传参（不改脚本）：
#   bash scripts/shell/download.sh Qwen/Qwen2.5-Coder-14B-Instruct

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

# 可选：自定义镜像，cp scripts/shell/mirrors.env.example scripts/shell/mirrors.env
if [[ -f scripts/shell/mirrors.env ]]; then
  # shellcheck disable=SC1091
  source scripts/shell/mirrors.env
fi

export HF_HOME="${HF_HOME:-/mnt/cache/tonghao2/data/cache}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

# hf-mirror 不支持 XET 存储，大模型（如 Qwen3.5-122B）需禁用否则会 401
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"

# 大模型并发过高易触发 429，默认单线程下载
export HF_DOWNLOAD_MAX_WORKERS="${HF_DOWNLOAD_MAX_WORKERS:-1}"

# 使用 hf-mirror 时默认禁用系统代理，避免 SOCKS 代理缺 socksio 报错
# 若必须走代理下载，在 mirrors.env 里设 HF_UNSET_PROXY=0 并 pip install httpx[socks]
HF_UNSET_PROXY="${HF_UNSET_PROXY:-1}"
if [[ "${HF_UNSET_PROXY}" == "1" ]]; then
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
fi

download_model() {
  python scripts/download.py --model "$1"
}

download_dataset() {
  python scripts/download.py --data "$1"
}

# ---------- 下载列表（要什么就取消注释）----------

# download_model "Qwen/Qwen2.5-Coder-14B-Instruct"
# download_model "Qwen/Qwen3-Coder-30B-A3B-Instruct"
# download_model "Qwen/Qwen3.5-122B-A10B"
# download_model "Qwen/Qwen3.5-122B-A10B-FP8"
# download_model "deepseek-ai/DeepSeek-V3"

# download_dataset "seeklhy/SynSQL-2.5M"

# ---------- 以上 ----------

# 命令行传参：bash download.sh <model_id>
if [[ $# -gt 0 ]]; then
  download_model "$1"
  exit 0
fi

echo "请在脚本里取消注释要下载的模型，或："
echo "  bash scripts/shell/download.sh Qwen/Qwen2.5-Coder-14B-Instruct"
exit 1
