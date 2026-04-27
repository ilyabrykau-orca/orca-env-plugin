# Tests

## Layers

| Layer | Command | Cost | When |
|---|---|---|---|
| Static validation | `python3 ~/.claude/skills/md-generator/scripts/validate_plugin.py .` | Free | Every commit |
| Hook unit tests | `python3 ~/.claude/skills/md-generator/scripts/run_plugin_tests.py . --unit` | Free | Every commit |
| E2E evals | `python3 ~/.claude/skills/md-generator/scripts/run_plugin_tests.py . --e2e` | ~$0.50 | PR + release |

## Running locally

```bash
# Static + unit (no API key needed)
python3 ~/.claude/skills/md-generator/scripts/run_plugin_tests.py /path/to/orca-env-plugin --static --unit

# Full suite
ANTHROPIC_API_KEY=sk-... python3 ~/.claude/skills/md-generator/scripts/run_plugin_tests.py /path/to/orca-env-plugin --static --unit --e2e
```

## What's tested

- **`pretool-read-source`** — Read on .go source → denied
- **`pretool-edit-source`** — Edit on .ts source → denied
- **`pretool-write-source`** — Write on .py source → denied
- **`pretool-edit-non-source-allowed`** — Edit on .md → passes
- **`pretool-edit-outside-prefix-allowed`** — Edit outside ~/src → passes
- **`pretool-edit-exempt-vendor-allowed`** — Edit in vendor/ → passes
- **`pretool-grep-watched`** — Grep under ~/src → denied
- **`pretool-bash-rtk-rewrite`** — Plain Bash → rewritten via rtk
- **`pretool-bash-rtk-skip-pipeline`** — Bash with pipe → falls through
- **`pretool-bash-rtk-claude-raw`** — CLAUDE_RAW=1 → falls through
- **`posttool-find-refs`** — find_referencing_symbols → state file created
- **`pretool-serena-edit-without-refs`** — Serena edit without prior find_refs → denied
- **`pretool-serena-edit-with-refs`** — Serena edit after find_refs → allowed
- **`posttoolbatch-clean`** — Clean batch → logged, no block
- **`posttoolbatch-violation`** — Native source tool in batch → `decision: block`
- **`instructionsloaded-claudemd`** — CLAUDE.md load → `last-routing-load.json` written
- **`sessionstart-startup`** — Full routing block injected
- **`sessionstart-compact`** — Compact routing block injected
- **`userpromptexpansion-skill`** — /orca-dev → routing context injected
- **`pretool-edit-path-with-spaces`** — Path with spaces → denied (no shell quoting bug)
- **`posttool-parallel-session-a`** — Per-session state scoping works

## What's NOT enforced

This plugin ships three independent enforcement layers:

1. `PreToolUse permissionDecision: deny` + exit 2
2. `permissions.deny` in settings.json
3. `PostToolBatch` audit + `decision: block`

Known Claude Code issues ([#37210](https://github.com/anthropics/claude-code/issues/37210), [#33106](https://github.com/anthropics/claude-code/issues/33106)) can let `Edit` and MCP-tool calls slip through the PreToolUse deny. In those cases, `permissions.deny` still blocks. If both fail, PostToolBatch surfaces the violation in the next turn. None of these is airtight in isolation; together they hold in production.
