"""模型注册表：根路径 + 子路径 + 对外服务名。"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

# 本地权重根目录（启动脚本中 MODELS_ROOT 可覆盖）
MODELS_ROOT = Path("/mnt/cache/tonghao2/data/models")


@dataclass(frozen=True)
class ModelSpec:
    sub_path: str
    served_model_name: str
    hf_id: str | None = None
    max_model_len: int = 32768
    gpu_memory_utilization: float = 0.90
    tensor_parallel_size: int | None = None
    vllm_extra_args: str | None = None
    notes: str = ""


MODELS: dict[str, ModelSpec] = {
    "qwen2.5-coder-3b": ModelSpec(
        sub_path="Qwen/Qwen2.5-Coder-3B-Instruct",
        served_model_name="qwen2.5-coder-3b",
        hf_id="Qwen/Qwen2.5-Coder-3B-Instruct",
        notes="轻量联调",
    ),
    "qwen2.5-coder-7b": ModelSpec(
        sub_path="Qwen/Qwen2.5-Coder-7B-Instruct",
        served_model_name="qwen2.5-coder-7b",
        hf_id="Qwen/Qwen2.5-Coder-7B-Instruct",
        notes="速度快，约 16GB 显存",
    ),
    "qwen2.5-coder-14b": ModelSpec(
        sub_path="Qwen/Qwen2.5-Coder-14B-Instruct",
        served_model_name="qwen2.5-coder-14b",
        hf_id="Qwen/Qwen2.5-Coder-14B-Instruct",
        notes="默认推荐，A800 80GB",
    ),
    "qwen2.5-coder-32b": ModelSpec(
        sub_path="Qwen/Qwen2.5-Coder-32B-Instruct",
        served_model_name="qwen2.5-coder-32b",
        hf_id="Qwen/Qwen2.5-Coder-32B-Instruct",
        max_model_len=8192,           # 单卡 A800 80GB：权重约 65GB，上下文不宜过大
        gpu_memory_utilization=0.95,
        notes="强 coding，单卡 A800 建议 max_model_len<=8192",
    ),
    "qwen3-coder-30b-a3b": ModelSpec(
        sub_path="Qwen/Qwen3-Coder-30B-A3B-Instruct",
        served_model_name="qwen3-coder-30b-a3b",
        hf_id="Qwen/Qwen3-Coder-30B-A3B-Instruct",
        notes="MoE coding",
    ),
    "qwen3.5-122b-a10b": ModelSpec(
        sub_path="Qwen/Qwen3.5-122B-A10B",
        served_model_name="qwen3.5-122b-a10b",
        hf_id="Qwen/Qwen3.5-122B-A10B",
        max_model_len=262144,
        tensor_parallel_size=8,
        vllm_extra_args="--reasoning-parser qwen3 --max-num-seqs 256",
        notes="BF16，官方 8 卡配置",
    ),
    "qwen3.5-122b-a10b-fp8": ModelSpec(
        sub_path="Qwen/Qwen3.5-122B-A10B-FP8",
        served_model_name="qwen3.5-122b-a10b-fp8",
        hf_id="Qwen/Qwen3.5-122B-A10B-FP8",
        max_model_len=262144,
        tensor_parallel_size=8,
        vllm_extra_args="--reasoning-parser qwen3 --max-num-seqs 256",
        notes="FP8 量化，8x A800/H100 80GB",
    ),
}


def resolve_model(key: str, models_root: str | Path | None = None) -> dict[str, str | int | float]:
    if key not in MODELS:
        available = ", ".join(sorted(MODELS))
        raise KeyError(f"Unknown MODEL_KEY: {key}. Available: {available}")

    root = Path(models_root) if models_root else MODELS_ROOT
    spec = MODELS[key]
    resolved: dict[str, str | int | float] = {
        "MODEL_PATH": str(root / spec.sub_path),
        "SERVED_MODEL_NAME": spec.served_model_name,
        "MAX_MODEL_LEN": spec.max_model_len,
        "GPU_MEM_UTIL": spec.gpu_memory_utilization,
    }
    if spec.tensor_parallel_size is not None:
        resolved["TENSOR_PARALLEL_SIZE"] = spec.tensor_parallel_size
    if spec.vllm_extra_args:
        resolved["VLLM_EXTRA_ARGS"] = spec.vllm_extra_args
    return resolved


def shell_exports(key: str, models_root: str | Path | None = None) -> str:
    """生成 bash export 语句，供 scripts/shell/start.sh 使用。"""
    resolved = resolve_model(key, models_root=models_root)
    lines: list[str] = []
    for name, value in resolved.items():
        escaped = str(value).replace("'", "'\\''")
        lines.append(f"export {name}='{escaped}'")
    return "\n".join(lines)


if __name__ == "__main__":
    import os
    import sys

    model_key = os.environ.get("MODEL_KEY") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not model_key:
        print("Usage: MODEL_KEY=<key> python config/config.py", file=sys.stderr)
        sys.exit(1)
    try:
        print(shell_exports(model_key, models_root=os.environ.get("MODELS_ROOT")))
    except KeyError as exc:
        print(f"echo '{exc}' >&2", file=sys.stderr)
        print("exit 1")
