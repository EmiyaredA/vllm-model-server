#!/usr/bin/env python
"""Minimal OpenAI-compatible client for the local vLLM server."""

from __future__ import annotations

import argparse
import os
import sys

from openai import OpenAI


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Send a chat request to the local vLLM server.")
    parser.add_argument(
        "--base-url",
        default=os.environ.get("VLLM_BASE_URL", "http://127.0.0.1:8000/v1"),
        help="OpenAI-compatible base URL",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("API_KEY", "EMPTY"),
        help="API key (use EMPTY if auth is disabled)",
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("SERVED_MODEL_NAME", "qwen2.5-coder-14b"),
        help="Served model name",
    )
    parser.add_argument(
        "--prompt",
        default="Write a Python function that checks whether a string is a palindrome.",
        help="User message",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    client = OpenAI(base_url=args.base_url, api_key=args.api_key or "EMPTY")

    response = client.chat.completions.create(
        model=args.model,
        messages=[
            {"role": "system", "content": "You are a helpful coding assistant."},
            {"role": "user", "content": args.prompt},
        ],
        temperature=0.2,
        max_tokens=512,
    )

    print(response.choices[0].message.content)
    return 0


if __name__ == "__main__":
    sys.exit(main())
