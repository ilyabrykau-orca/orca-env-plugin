#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p dist

bun build src/index.ts \
  --compile \
  --minify \
  --bytecode \
  --sourcemap=inline \
  --target=bun \
  --outfile dist/claude-toolkit

chmod +x dist/claude-toolkit
echo "Built dist/claude-toolkit ($(wc -c < dist/claude-toolkit | tr -d ' ') bytes)"
