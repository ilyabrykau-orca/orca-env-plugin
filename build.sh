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

# bun 1.3.x produces binaries with an invalid placeholder signature that macOS 15.4+ rejects.
# Strip and re-sign with ad-hoc identity so the binary executes.
codesign --remove-signature dist/claude-toolkit 2>/dev/null || true
codesign --sign - dist/claude-toolkit 2>/dev/null || true

echo "Built dist/claude-toolkit ($(wc -c < dist/claude-toolkit | tr -d ' ') bytes)"
