#!/usr/bin/env python
# coding=utf-8
"""Download models/datasets from Hugging Face Hub."""

from __future__ import annotations

import argparse
import os
import shutil
import time
import traceback
from pathlib import Path

from huggingface_hub import snapshot_download
from huggingface_hub.errors import HfHubHTTPError, IncompleteSnapshotError
from tqdm import tqdm

DEFAULT_MAX_WORKERS = int(os.environ.get("HF_DOWNLOAD_MAX_WORKERS", "1"))
DEFAULT_RETRY_BASE_SEC = float(os.environ.get("HF_DOWNLOAD_RETRY_BASE_SEC", "30"))
DEFAULT_RETRY_MAX_SEC = float(os.environ.get("HF_DOWNLOAD_RETRY_MAX_SEC", "600"))

DEFAULT_MODELS_ROOT = Path("/mnt/cache/tonghao2/data/models")
DEFAULT_DATASETS_ROOT = Path("/mnt/cache/tonghao2/data/datasets")
DEFAULT_CACHE_DIR = Path("/mnt/cache/tonghao2/data/cache")


def _ensure_hf_home(cache_dir: Path) -> None:
    cache_dir.mkdir(parents=True, exist_ok=True)
    os.environ["HF_HOME"] = str(cache_dir)


def default_model_path(huggingface_path: str, models_root: Path = DEFAULT_MODELS_ROOT) -> Path:
    return models_root / huggingface_path


def default_dataset_path(huggingface_path: str, datasets_root: Path = DEFAULT_DATASETS_ROOT) -> Path:
    return datasets_root / huggingface_path


def _retry_wait_seconds(attempt: int, exc: BaseException) -> float:
    base = DEFAULT_RETRY_BASE_SEC
    if isinstance(exc, HfHubHTTPError) and exc.response is not None and exc.response.status_code == 429:
        base = max(base, 60.0)
    if isinstance(exc, IncompleteSnapshotError) and "429" in str(exc):
        base = max(base, 60.0)
    return min(base * (2 ** max(attempt - 1, 0)), DEFAULT_RETRY_MAX_SEC)


def download_model(
    huggingface_path: str,
    local_path: str | Path,
    *,
    cache_dir: Path | None = None,
    allow_patterns: list[str] | None = None,
    max_workers: int = DEFAULT_MAX_WORKERS,
) -> None:
    if cache_dir is not None:
        _ensure_hf_home(cache_dir)

    local_path = Path(local_path)
    local_path.mkdir(parents=True, exist_ok=True)

    attempt = 0
    while True:
        attempt += 1
        try:
            snapshot_download(
                huggingface_path,
                allow_patterns=allow_patterns,
                local_dir=str(local_path),
                ignore_patterns=["*.onnx"],
                force_download=False,
                max_workers=max_workers,
            )
            break
        except KeyboardInterrupt:
            break
        except Exception as exc:
            traceback.print_exc()
            wait = _retry_wait_seconds(attempt, exc)
            print(f"Download failed, retrying in {wait:.0f}s (attempt {attempt})...")
            time.sleep(wait)


def download_data(
    huggingface_path: str,
    local_path: str | Path,
    *,
    cache_dir: Path | None = None,
    allow_patterns: list[str] | None = None,
    max_workers: int = DEFAULT_MAX_WORKERS,
) -> None:
    if cache_dir is not None:
        _ensure_hf_home(cache_dir)

    local_path = Path(local_path)
    local_path.mkdir(parents=True, exist_ok=True)

    attempt = 0
    while True:
        attempt += 1
        try:
            snapshot_download(
                huggingface_path,
                allow_patterns=allow_patterns,
                local_dir=str(local_path),
                repo_type="dataset",
                local_dir_use_symlinks=True,
                max_workers=max_workers,
            )
            break
        except KeyboardInterrupt:
            break
        except Exception as exc:
            traceback.print_exc()
            wait = _retry_wait_seconds(attempt, exc)
            print(f"Download failed, retrying in {wait:.0f}s (attempt {attempt})...")
            time.sleep(wait)


def transfer_soft_link(src: str | Path, dst: str | Path) -> None:
    src = Path(src)
    dst = Path(dst)
    dst.mkdir(parents=True, exist_ok=True)

    for file in tqdm(os.listdir(src)):
        src_file = src / file
        if src_file.is_symlink():
            blob = src / os.readlink(src_file)
        else:
            blob = src_file
        shutil.move(str(blob), str(dst / file))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Download models or datasets from Hugging Face Hub.")
    parser.add_argument(
        "-m",
        "--model",
        help="Hugging Face model repo id, e.g. Qwen/Qwen2.5-Coder-14B-Instruct",
    )
    parser.add_argument(
        "-d",
        "--data",
        help="Hugging Face dataset repo id",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Local output directory. Defaults to models/datasets root + repo id.",
    )
    parser.add_argument(
        "--models-root",
        default=str(DEFAULT_MODELS_ROOT),
        help=f"Root directory for models (default: {DEFAULT_MODELS_ROOT})",
    )
    parser.add_argument(
        "--datasets-root",
        default=str(DEFAULT_DATASETS_ROOT),
        help=f"Root directory for datasets (default: {DEFAULT_DATASETS_ROOT})",
    )
    parser.add_argument(
        "--cache-dir",
        default=str(DEFAULT_CACHE_DIR),
        help=f"Hugging Face cache directory (default: {DEFAULT_CACHE_DIR})",
    )
    parser.add_argument(
        "--allow-patterns",
        nargs="+",
        help="Optional file patterns to download",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=DEFAULT_MAX_WORKERS,
        help=(
            "Concurrent download workers (default: %(default)s, "
            "or HF_DOWNLOAD_MAX_WORKERS env). Use 1 for large models to avoid 429."
        ),
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if not args.model and not args.data:
        parser.error("one of --model or --data is required")

    cache_dir = Path(args.cache_dir)
    _ensure_hf_home(cache_dir)

    if args.model:
        output = Path(args.output) if args.output else default_model_path(args.model, Path(args.models_root))
        print(f"Downloading model {args.model} -> {output}")
        download_model(
            args.model,
            output,
            cache_dir=cache_dir,
            allow_patterns=args.allow_patterns,
            max_workers=args.max_workers,
        )
        print(f"Done: {output}")

    if args.data:
        output = Path(args.output) if args.output else default_dataset_path(args.data, Path(args.datasets_root))
        print(f"Downloading dataset {args.data} -> {output}")
        download_data(
            args.data,
            output,
            cache_dir=cache_dir,
            allow_patterns=args.allow_patterns,
            max_workers=args.max_workers,
        )
        print(f"Done: {output}")


if __name__ == "__main__":
    main()
