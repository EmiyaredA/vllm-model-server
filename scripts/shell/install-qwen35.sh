#!/usr/bin/env bash
# 安装 Qwen3.5 专用 conda 环境（vLLM nightly，支持 qwen3_5_moe）
#
# 用法：
#   cd /mnt/cache/tonghao2/slns/vllm-model-server
#   bash scripts/shell/install-qwen35.sh --recreate    # 删旧环境，全新安装（推荐）
#   bash scripts/shell/install-qwen35.sh               # 环境已存在则跳过创建
#
# 与 install.sh（vllm 0.8.5 / Qwen2.5）并存，默认环境名：vllm-qwen35
# Qwen 官方要求 nightly：https://wheels.vllm.ai/nightly

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="${ROOT_DIR}/scripts/shell"
MIRRORS_FILE="${SHELL_DIR}/mirrors.env"
MODEL_CONFIG_DIR="${MODELS_ROOT:-/mnt/cache/tonghao2/data/models}/Qwen/Qwen3.5-122B-A10B"
VLLM_NIGHTLY_INDEX="${VLLM_NIGHTLY_INDEX:-https://wheels.vllm.ai/nightly}"

if [[ -f "${MIRRORS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${MIRRORS_FILE}"
fi

ENV_NAME="${CONDA_ENV_NAME:-vllm-qwen35}"
RECREATE=0
[[ "${1:-}" == "--recreate" ]] && RECREATE=1

PIP_INDEX="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
CONDA_FORGE_MIRROR="${CONDA_FORGE_MIRROR:-}"

log() { echo "[install-qwen35] $*"; }
die() { echo "[install-qwen35] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

configure_pip_mirror() {
  mkdir -p "${HOME}/.pip"
  cat > "${HOME}/.pip/pip.conf" <<EOF
[global]
index-url = ${PIP_INDEX}
trusted-host = ${PIP_HOST}
timeout = 120
retries = 10
EOF
  log "pip mirror: ${PIP_INDEX}"
}

configure_conda_mirror() {
  if [[ -n "${CONDA_FORGE_MIRROR}" ]]; then
    log "conda-forge mirror: ${CONDA_FORGE_MIRROR}"
    conda config --prepend channels "${CONDA_FORGE_MIRROR}" >/dev/null 2>&1 || true
  fi
}

setup_conda_env() {
  if [[ "${RECREATE}" -eq 1 ]] && conda env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
    log "removing env: ${ENV_NAME}"
    conda env remove -n "${ENV_NAME}" -y
  fi

  if conda env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
    log "conda env exists: ${ENV_NAME}"
    return 0
  fi

  log "creating conda env: ${ENV_NAME} (python=3.11)"
  conda create -n "${ENV_NAME}" python=3.11 pip pyyaml -c conda-forge -y
}

pip_install() {
  local py="${1}"

  log "upgrading pip..."
  "${py}" -m pip install --upgrade pip setuptools wheel \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"

  # Qwen 官方：fresh env + nightly wheel；torch 由 nighty / 依赖解析拉取，不锁 cu124/2.6.0
  log "installing vLLM from nightly (${VLLM_NIGHTLY_INDEX}) ..."
  if ! "${py}" -m pip install -U \
    "vllm" \
    "huggingface-hub>=0.27.0" \
    "tqdm>=4.66.0" \
    "openai>=1.50.0" \
    "socksio>=1.0.0" \
    --extra-index-url "${VLLM_NIGHTLY_INDEX}" \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"; then
    log "primary mirror failed, retry Aliyun + nightly ..."
    PIP_INDEX="https://mirrors.aliyun.com/pypi/simple/"
    PIP_HOST="mirrors.aliyun.com"
    configure_pip_mirror
    "${py}" -m pip install -U \
      "vllm" \
      "huggingface-hub>=0.27.0" \
      "tqdm>=4.66.0" \
      "openai>=1.50.0" \
      "socksio>=1.0.0" \
      --extra-index-url "${VLLM_NIGHTLY_INDEX}" \
      -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"
  fi

  # 确保能识别 qwen3_5_moe（nightly 可能已带够新的 transformers，这里兜底抬升）
  log "ensuring transformers recognizes qwen3_5_moe ..."
  "${py}" -m pip install -U \
    "transformers>=4.57.0" \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}" || \
  "${py}" -m pip install -U \
    "transformers>=4.57.0" \
    -i "https://mirrors.aliyun.com/pypi/simple/" --trusted-host "mirrors.aliyun.com"
}

verify_install() {
  local py="${1}"
  log "verifying..."
  MODEL_CONFIG_DIR="${MODEL_CONFIG_DIR}" "${py}" - <<'PY'
import os
import sys

import torch
import transformers
import vllm
from transformers import AutoConfig
from transformers.models.auto.configuration_auto import CONFIG_MAPPING

print("torch:", torch.__version__, "| cuda:", torch.version.cuda)
print("vllm:", vllm.__version__)
print("transformers:", transformers.__version__)

if "qwen3_5_moe" not in CONFIG_MAPPING:
    raise SystemExit(
        "transformers CONFIG_MAPPING missing 'qwen3_5_moe'; "
        f"got keys sample={list(CONFIG_MAPPING.keys())[-10:]}"
    )
print("CONFIG_MAPPING: qwen3_5_moe OK")

model_dir = os.environ.get("MODEL_CONFIG_DIR", "")
if model_dir and os.path.isdir(model_dir):
    cfg = AutoConfig.from_pretrained(model_dir, trust_remote_code=True)
    model_type = getattr(cfg, "model_type", None)
    print("local model_type:", model_type)
    if model_type not in ("qwen3_5_moe", "qwen3_5_moe_text"):
        print("WARNING: unexpected model_type", model_type, file=sys.stderr)
else:
    print("skip AutoConfig local check (model dir missing):", model_dir)

if torch.cuda.is_available():
    print("gpu0:", torch.cuda.get_device_name(0))
else:
    print("WARNING: CUDA not available in this process (driver/runtime mismatch?)")
PY
  command -v vllm >/dev/null && vllm --help 2>&1 | head -5 || true
  if command -v vllm >/dev/null; then
    if vllm serve --help 2>&1 | grep -q "reasoning-parser"; then
      log "reasoning-parser choices:"
      vllm serve --help 2>&1 | grep -A2 "reasoning-parser" | head -5 || true
    fi
  fi
}

main() {
  require_cmd conda
  cd "${ROOT_DIR}"
  configure_conda_mirror
  configure_pip_mirror
  setup_conda_env

  # shellcheck disable=SC1091
  eval "$(conda shell.bash hook)"
  conda activate "${ENV_NAME}"

  local py
  py="$(command -v python)"
  log "python: ${py} ($(${py} -V 2>&1))"

  pip_install "${py}"
  verify_install "${py}"

  cat <<EOF

Done. Qwen3.5 env ready (vLLM nightly).

  conda activate ${ENV_NAME}
  bash scripts/shell/start.sh

旧环境 vllm-model-server（0.8.5）未改动，仍可用于 Qwen2.5 / Qwen3-Coder。
记录版本便于复现: pip show vllm transformers torch

EOF
}

main "$@"
