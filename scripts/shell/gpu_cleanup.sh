#!/usr/bin/env bash
# 查看 / 清理 GPU 显存占用
#
#   bash scripts/shell/gpu_cleanup.sh          # 只看状态
#   bash scripts/shell/gpu_cleanup.sh --kill     # 结束所有占 GPU 的进程
#   bash scripts/shell/gpu_cleanup.sh --kill-vllm  # 只杀 vllm / api_server

set -euo pipefail

if ! command -v nvidia-smi &>/dev/null; then
  echo "未找到 nvidia-smi" >&2
  exit 1
fi

echo "=== GPU 概览 ==="
nvidia-smi

echo
echo "=== 占显存进程 ==="
mapfile -t rows < <(nvidia-smi --query-compute-apps=gpu_bus_id,pid,process_name,used_gpu_memory --format=csv,noheader 2>/dev/null || true)

if [[ ${#rows[@]} -eq 0 || -z "${rows[0]// }" ]]; then
  echo "(无计算进程；若显存仍被占用，可能是驱动残留，可试 --kill 或重启容器)"
else
  printf '%s\n' "${rows[@]}"
fi

mode="${1:-}"

collect_pids() {
  local pattern="${1:-}"
  local pids=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local pid name
    pid=$(echo "$line" | awk -F', ' '{print $2}')
    name=$(echo "$line" | awk -F', ' '{print $3}')
    if [[ -z "$pattern" || "$name" == *"$pattern"* ]]; then
      pids+=("$pid")
    fi
  done < <(nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader 2>/dev/null || true)
  printf '%s\n' "${pids[@]}" | sort -u
}

kill_pids() {
  local label=$1
  shift
  local pids=("$@")
  if [[ ${#pids[@]} -eq 0 ]]; then
    echo "没有可清理的 ${label} 进程"
    return 0
  fi
  echo "结束 ${label} 进程: ${pids[*]}"
  kill "${pids[@]}" 2>/dev/null || true
  sleep 2
  for pid in "${pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "强制结束: $pid"
      kill -9 "$pid" 2>/dev/null || true
    fi
  done
}

case "$mode" in
  --kill)
    mapfile -t all_pids < <(collect_pids)
    kill_pids "GPU" "${all_pids[@]:-}"
    ;;
  --kill-vllm)
    mapfile -t vllm_pids < <(collect_pids "VLLM")
    mapfile -t api_pids < <(collect_pids "api_server")
    mapfile -t python_pids < <(collect_pids "python")
    # vllm 常以 VLLM:: 或 python -m vllm 出现，合并去重
    pids=($(printf '%s\n' "${vllm_pids[@]:-}" "${api_pids[@]:-}" | sort -u))
    if [[ ${#pids[@]} -eq 0 ]]; then
      echo "未找到 vllm 进程，尝试 --kill 清理全部 GPU 进程"
      exit 1
    fi
    kill_pids "vLLM" "${pids[@]}"
    ;;
  "")
  # 仅查看
    ;;
  *)
    echo "用法: $0 [--kill | --kill-vllm]" >&2
    exit 1
    ;;
esac

if [[ "$mode" == --kill || "$mode" == --kill-vllm ]]; then
  echo
  echo "=== 清理后 ==="
  nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv
fi
