#!/usr/bin/env bash
# 启动 vLLM 服务
#
#   conda activate vllm-model-server
#   bash scripts/shell/start.sh
#
# 模型列表见 config/config.py

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# ── 配置 ──────────────────────────────────────────
MODELS_ROOT=/mnt/cache/tonghao2/data/models
MODEL_KEY=qwen2.5-coder-32b          # config/config.py 中的 key
HOST=0.0.0.0
PORT=8000
TENSOR_PARALLEL_SIZE=1               # 单卡填 1；多卡填卡数
HF_HOME=/mnt/cache/tonghao2/data/cache
CUDA_VISIBLE_DEVICES=1               # 指定 GPU（0-7），注释掉则用全部
export VLLM_USE_V1=0                 # vllm 0.8.x 建议关闭 v1 引擎

# 可选
# API_KEY=
# HF_TOKEN=
# MAX_MODEL_LEN=8192
# GPU_MEM_UTIL=0.95
# VLLM_EXTRA_ARGS="--max-num-seqs 64"
# ─────────────────────────────────────────────────

export MODEL_KEY MODELS_ROOT HF_HOME VLLM_USE_V1
[[ -n "${CUDA_VISIBLE_DEVICES:-}" ]] && export CUDA_VISIBLE_DEVICES
eval "$(python config/config.py)"

: "${MODEL_PATH:?未知 MODEL_KEY: ${MODEL_KEY}，请检查 config/config.py}"

if [[ ! -d "$MODEL_PATH" ]]; then
  echo "模型目录不存在: $MODEL_PATH" >&2
  exit 1
fi

if ! command -v vllm &>/dev/null; then
  echo "未找到 vllm，请先: bash scripts/shell/install.sh --recreate" >&2
  exit 1
fi

echo "启动 vLLM"
echo "  路径:   $MODEL_PATH"
echo "  名称:   $SERVED_MODEL_NAME"
echo "  地址:   $HOST:$PORT"
echo "  卡数:   $TENSOR_PARALLEL_SIZE"
[[ -n "${CUDA_VISIBLE_DEVICES:-}" ]] && echo "  设备:   $CUDA_VISIBLE_DEVICES"

ARGS=(
  serve "$MODEL_PATH"
  --host "$HOST"
  --port "$PORT"
  --max-model-len "${MAX_MODEL_LEN:-32768}"
  --gpu-memory-utilization "${GPU_MEM_UTIL:-0.90}"
  --served-model-name "$SERVED_MODEL_NAME"
)

[[ -n "${API_KEY:-}" ]] && ARGS+=(--api-key "$API_KEY")
[[ "${TENSOR_PARALLEL_SIZE:-1}" -gt 1 ]] && ARGS+=(--tensor-parallel-size "$TENSOR_PARALLEL_SIZE")

if [[ -n "${VLLM_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  ARGS+=(${VLLM_EXTRA_ARGS})
fi

vllm "${ARGS[@]}"
