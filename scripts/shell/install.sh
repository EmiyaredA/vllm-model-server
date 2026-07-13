#!/usr/bin/env bash
# 安装 conda 环境 + vLLM（适配 NVIDIA 驱动 535 / CUDA 12.4）
#
# 用法：
#   cd /mnt/cache/tonghao2/slns/vllm-model-server
#   bash scripts/shell/install.sh --recreate    # 删旧环境，全新安装（推荐）
#   bash scripts/shell/install.sh               # 环境已存在则跳过创建
#
# 版本锁定（cu124 索引最高 torch 2.6.0，与 vllm 0.8.5 官方依赖一致）：
#   torch==2.6.0  torchvision==0.21.0  torchaudio==2.6.0  vllm==0.8.5
#   transformers==4.51.3  tokenizers==0.21.1

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="${ROOT_DIR}/scripts/shell"
MIRRORS_FILE="${SHELL_DIR}/mirrors.env"

if [[ -f "${MIRRORS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${MIRRORS_FILE}"
fi

ENV_NAME="${CONDA_ENV_NAME:-vllm-model-server}"
RECREATE=0
[[ "${1:-}" == "--recreate" ]] && RECREATE=1

# ── 锁定版本（勿随意改，避免与驱动 CUDA 12.4 冲突）──
VLLM_VERSION="0.8.5"
TORCH_VERSION="2.6.0"
TORCHVISION_VERSION="0.21.0"
TORCHAUDIO_VERSION="2.6.0"
TORCH_INDEX="https://download.pytorch.org/whl/cu124"
TRANSFORMERS_VERSION="4.51.3"
TOKENIZERS_VERSION="0.21.1"

PIP_INDEX="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
CONDA_FORGE_MIRROR="${CONDA_FORGE_MIRROR:-}"

log() { echo "[install] $*"; }
die() { echo "[install] ERROR: $*" >&2; exit 1; }

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

  log "creating conda env: ${ENV_NAME}"
  if [[ -f "${ROOT_DIR}/environment.yml" ]]; then
    conda env create -f "${ROOT_DIR}/environment.yml"
  else
    conda create -n "${ENV_NAME}" python=3.10 pip pyyaml -c conda-forge -y
  fi
}

pip_install() {
  local py="${1}"

  log "upgrading pip..."
  "${py}" -m pip install --upgrade pip setuptools wheel \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"

  log "installing PyTorch ${TORCH_VERSION} (${TORCH_INDEX}) ..."
  "${py}" -m pip install \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url "${TORCH_INDEX}"

  log "installing vllm==${VLLM_VERSION} + tools ..."
  if ! "${py}" -m pip install \
    "vllm==${VLLM_VERSION}" \
    "huggingface-hub>=0.27.0" \
    "tqdm>=4.66.0" \
    "openai>=1.50.0" \
    "socksio>=1.0.0" \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"; then
    log "primary mirror failed, retry Aliyun..."
    PIP_INDEX="https://mirrors.aliyun.com/pypi/simple/"
    PIP_HOST="mirrors.aliyun.com"
    configure_pip_mirror
    "${py}" -m pip install \
      "vllm==${VLLM_VERSION}" \
      "huggingface-hub>=0.27.0" \
      "tqdm>=4.66.0" \
      "openai>=1.50.0" \
      "socksio>=1.0.0" \
      -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"
  fi

  # 防止 vllm 把 torch 升到 cu130，并锁定 transformers（新版会缺 all_special_tokens_extended）
  log "pinning torch + transformers ..."
  "${py}" -m pip install \
    "torch==${TORCH_VERSION}" \
    "torchvision==${TORCHVISION_VERSION}" \
    "torchaudio==${TORCHAUDIO_VERSION}" \
    --index-url "${TORCH_INDEX}" --force-reinstall
  "${py}" -m pip install \
    "transformers==${TRANSFORMERS_VERSION}" \
    "tokenizers==${TOKENIZERS_VERSION}" \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"
}

verify_install() {
  local py="${1}"
  log "verifying..."
  "${py}" - <<'PY'
import torch
import vllm
import transformers

ver = torch.__version__
if not ver.startswith("2.6.0"):
    raise SystemExit(f"unexpected torch {ver}, want 2.6.0+cu124")
if torch.version.cuda != "12.4":
    raise SystemExit(f"unexpected cuda {torch.version.cuda}, want 12.4")
if not torch.cuda.is_available():
    raise SystemExit("CUDA not available")
print("torch:", ver, "| cuda:", torch.version.cuda)
print("gpu0:", torch.cuda.get_device_name(0))
print("vllm:", vllm.__version__)
print("transformers:", transformers.__version__)
PY
  vllm --help | head -3
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
  log "python: ${py}"

  pip_install "${py}"
  verify_install "${py}"

  cat <<EOF

Done.

  conda activate ${ENV_NAME}
  bash scripts/shell/start.sh

EOF
}

main "$@"
