#!/usr/bin/env python3
"""Parse a claude stream-json transcript and assert on which tools were called."""
import argparse, json, re, sys
from pathlib import Path


def extract_tool_calls(transcript_path: str) -> list[str]:
    tools = []
    with open(transcript_path, errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            # Tolerant extraction — schema shifts across versions
            for name in _find_tool_names(obj):
                tools.append(name)
    return tools


def _find_tool_names(obj, depth=0):
    if depth > 8:
        return
    if isinstance(obj, dict):
        if "name" in obj and isinstance(obj["name"], str) and obj.get("type") == "tool_use":
            yield obj["name"]
        if "tool_name" in obj and isinstance(obj["tool_name"], str):
            yield obj["tool_name"]
        for v in obj.values():
            yield from _find_tool_names(v, depth + 1)
    elif isinstance(obj, list):
        for item in obj:
            yield from _find_tool_names(item, depth + 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcript", required=True)
    ap.add_argument("--spec", required=True)
    ap.add_argument("--repo", default="/tmp/e2e-test-repo")
    args = ap.parse_args()

    spec = json.loads(args.spec)
    tools = extract_tool_calls(args.transcript)
    tool_set = set(tools)

    ok = True
    for must in spec.get("must_call_any", []):
        if must not in tool_set:
            print(f"  MISSING must_call_any: {must} (got {sorted(tool_set)})", file=sys.stderr)
            ok = False
    for must_not in spec.get("must_not_call", []):
        if must_not in tool_set:
            print(f"  UNEXPECTED must_not_call: {must_not}", file=sys.stderr)
            ok = False

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
