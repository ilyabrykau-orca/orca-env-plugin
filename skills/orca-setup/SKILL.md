---
name: orca-setup
description: Orca workspace setup — session init, project activation. For full routing params and recovery, use the routing-params skill.
---

# Orca Workspace Setup

## Session init

Call immediately on session start:
```
mcp__serena__activate_project(project=<detected-project>)
```

Full tool routing rules: read `~/.claude/ROUTING.md`.
For params/recovery reference: invoke `routing-params` skill.
