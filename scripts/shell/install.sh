#!/usr/bin/env bash
# Install conda env + vLLM dependencies with PyPI/Conda mirror support.
#
# Usage:
#   cd /mnt/cache/tonghao2/slns/vllm-model-server
#   bash scripts/shell/install.sh
#
# Optional:
#   cp scripts/shell/mirrors.env.example scripts/shell/mirrors.env
#   # edit mirrors.env, then:
#   bash scripts/shell/install.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHELL_DIR="${ROOT_DIR}/scripts/shell"
MIRRORS_FILE="${SHELL_DIR}/mirrors.env"

if [[ -f "${MIRRORS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${MIRRORS_FILE}"
fi

ENV_NAME="${CONDA_ENV_NAME:-vllm-model-server}"
PIP_INDEX="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_HOST="${PIP_TRUSTED_HOST:-pypi.tuna.tsinghua.edu.cn}"
CONDA_FORGE_MIRROR="${CONDA_FORGE_MIRROR:-}"

log() {
  echo "[install] $*"
}

die() {
  echo "[install] ERROR: $*" >&2
  exit 1
}

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

create_conda_env() {
  if conda env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
    log "conda env already exists: ${ENV_NAME}"
    return 0
  fi

  log "creating conda env: ${ENV_NAME}"
  if [[ -f "${ROOT_DIR}/environment.yml" ]]; then
    conda env create -f "${ROOT_DIR}/environment.yml"
  else
    conda create -n "${ENV_NAME}" python=3.10 pip pyyaml -c conda-forge -y
  fi
}

pip_install_packages() {
  local py="${1}"
  local -a packages=(
    "vllm>=0.8.0"
    "huggingface-hub>=0.27.0"
    "tqdm>=4.66.0"
    "openai>=1.50.0"
    "socksio>=1.0.0"
  )

  log "upgrading pip..."
  "${py}" -m pip install --upgrade pip setuptools wheel \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"

  log "installing python packages (this may take several minutes)..."
  if ! "${py}" -m pip install "${packages[@]}" \
    -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"; then
    log "primary mirror failed, retrying with Aliyun mirror..."
    PIP_INDEX="https://mirrors.aliyun.com/pypi/simple/"
    PIP_HOST="mirrors.aliyun.com"
    configure_pip_mirror
    "${py}" -m pip install "${packages[@]}" \
      -i "${PIP_INDEX}" --trusted-host "${PIP_HOST}"
  fi
}

verify_install() {
  local py="${1}"
  log "verifying installation..."
  "${py}" - <<'PY'
import vllm
import huggingface_hub

print("vllm:", vllm.__version__)
print("huggingface_hub:", huggingface_hub.__version__)
PY
  log "vllm CLI:"
  if command -v vllm >/dev/null 2>&1; then
    vllm --help | head -5
  else
    "${py}" -m vllm.entrypoints.openai.api_server --help >/dev/null
    log "vllm module OK (CLI not on PATH, use: python -m vllm.entrypoints.openai.api_server)"
  fi
}

main() {
  require_cmd conda

  cd "${ROOT_DIR}"
  configure_conda_mirror
  configure_pip_mirror
  create_conda_env

  # shellcheck disable=SC1091
  eval "$(conda shell.bash hook)"
  conda activate "${ENV_NAME}"

  local py
  py="$(command -v python)"
  log "using python: ${py}"

  pip_install_packages "${py}"
  verify_install "${py}"

  cat <<EOF

Done.

Next steps:
  conda activate ${ENV_NAME}
  cp .env.example .env
  ./scripts/start.sh

Model download (optional):
  export HF_ENDPOINT=https://hf-mirror.com
  bash scripts/shell/download.sh Qwen/Qwen2.5-Coder-14B-Instruct

EOF
}

main "$@"
