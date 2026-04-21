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
  --outfile dist/orca-env-plugin

chmod +x dist/orca-env-plugin

# bun 1.3.x produces binaries with an invalid placeholder signature that macOS 15.4+ rejects.
# Strip and re-sign with ad-hoc identity so the binary executes.
codesign --remove-signature dist/orca-env-plugin 2>/dev/null || true
codesign --sign - dist/orca-env-plugin 2>/dev/null || true

echo "Built dist/orca-env-plugin ($(wc -c < dist/orca-env-plugin | tr -d ' ') bytes)"
