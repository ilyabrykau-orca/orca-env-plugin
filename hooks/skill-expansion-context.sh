#!/usr/bin/env bash
# UserPromptExpansion: inject routing context when /orca-dev is invoked directly.
# Direct /skill invocation bypasses PreToolUse on the Skill tool.
set -euo pipefail

jq -n '{
  hookSpecificOutput: {
    hookEventName: "UserPromptExpansion",
    additionalContext: "Direct /orca-dev invocation: routing rules apply. Source reads/searches use mcp__codebase-memory-mcp__*. Source writes use mcp__serena__* (call find_referencing_symbols first). Native Read/Edit/Grep/Glob on source files are denied by hook + permissions.deny."
  }
}'
exit 0
