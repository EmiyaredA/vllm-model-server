#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

run_python() {
  if command -v python >/dev/null 2>&1; then
    python "$@"
  elif command -v uv >/dev/null 2>&1; then
    uv run python "$@"
  else
    echo "python not found; activate conda env or install uv" >&2
    exit 1
  fi
}

run_vllm() {
  if command -v vllm >/dev/null 2>&1; then
    vllm "$@"
  elif command -v uv >/dev/null 2>&1; then
    uv run vllm "$@"
  else
    run_python -m vllm.entrypoints.openai.api_server "$@"
  fi
}

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

MODEL_KEY="${MODEL_KEY:-}"
if [[ -n "$MODEL_KEY" ]]; then
  # shellcheck disable=SC2046
  eval "$(run_python - <<'PY'
import os
import sys

try:
    import yaml
except ImportError:
    print("echo 'PyYAML is required to use MODEL_KEY. Install with: uv add pyyaml' >&2; exit 1", file=sys.stderr)
    sys.exit(1)

key = os.environ.get("MODEL_KEY", "")
with open("config/models.yaml", encoding="utf-8") as f:
    cfg = yaml.safe_load(f)

models = cfg.get("models", {})
if key not in models:
    print(f"echo 'Unknown MODEL_KEY: {key}' >&2", file=sys.stderr)
    print(f"echo 'Available: {', '.join(models)}' >&2", file=sys.stderr)
    print("exit 1")
    sys.exit(0)

entry = models[key]
mapping = {
    "MODEL_PATH": "local_path",
    "SERVED_MODEL_NAME": "served_model_name",
    "MAX_MODEL_LEN": "max_model_len",
    "GPU_MEM_UTIL": "gpu_memory_utilization",
    "TENSOR_PARALLEL_SIZE": "tensor_parallel_size",
    "VLLM_EXTRA_ARGS": "vllm_extra_args",
}
for env_name, field in mapping.items():
    value = entry.get(field)
    if value is not None:
        escaped = str(value).replace("'", "'\\''")
        print(f"export {env_name}='{escaped}'")
PY
)"
fi

: "${MODEL_PATH:?MODEL_PATH is required (set in .env or via MODEL_KEY)}"
: "${HOST:=0.0.0.0}"
: "${PORT:=8000}"
: "${MAX_MODEL_LEN:=32768}"
: "${GPU_MEM_UTIL:=0.90}"
: "${SERVED_MODEL_NAME:=default}"

if [[ ! -d "$MODEL_PATH" ]]; then
  echo "Model path does not exist: $MODEL_PATH" >&2
  exit 1
fi

if [[ ! -f "$MODEL_PATH/config.json" ]]; then
  echo "Warning: $MODEL_PATH/config.json not found; vLLM may fail to load the model." >&2
fi

export HF_HOME="${HF_HOME:-/mnt/cache/tonghao2/data/cache}"

CMD=(
  run_vllm serve "$MODEL_PATH"
  --host "$HOST"
  --port "$PORT"
  --max-model-len "$MAX_MODEL_LEN"
  --gpu-memory-utilization "$GPU_MEM_UTIL"
  --served-model-name "$SERVED_MODEL_NAME"
)

if [[ -n "${API_KEY:-}" ]]; then
  CMD+=(--api-key "$API_KEY")
fi

if [[ -n "${TENSOR_PARALLEL_SIZE:-}" ]] && [[ "${TENSOR_PARALLEL_SIZE}" -gt 1 ]]; then
  CMD+=(--tensor-parallel-size "${TENSOR_PARALLEL_SIZE}")
fi

if [[ -n "${VLLM_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=(${VLLM_EXTRA_ARGS})
  CMD+=("${EXTRA_ARGS[@]}")
fi

echo "Starting vLLM:"
echo "  model: $MODEL_PATH"
echo "  served as: $SERVED_MODEL_NAME"
echo "  listen: $HOST:$PORT"

exec "${CMD[@]}"
