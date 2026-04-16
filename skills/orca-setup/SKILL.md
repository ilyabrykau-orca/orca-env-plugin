---
name: orca-setup
description: Orca workspace setup — tool routing enforcement, codebase-memory-mcp/Serena patterns, RTK workflow, memory protocol.
---

# Orca Workspace Setup

## TOOL ENFORCEMENT ACTIVE

Native `Read`, `Edit`, `Write`, `Grep`, `Glob`, `Search` are **HARD-BLOCKED** on code files or code-search workflows.
Use `codebase-memory-mcp` for indexed code exploration, `Serena` for symbolic edits, and `RTK` for compact Bash output.

Non-code files (.json, .yaml, .md, .toml, .cfg) → native tools allowed.
Composite shell commands (`|`, redirects, heredocs, `&&`, `||`, `;`) bypass RTK automatically so raw debugging still works.

---

## Step 1: Activate Project

Execute immediately:

```
mcp__serena__activate_project(project=<detected-project>)
```

Then load memories:

```
mcp__serena__list_memories()
mcp__serena__read_memory(memory_file_name="cross_project_map")
```

---

## Step 2: Tool Routing

### Search Code (preferred: codebase-memory-mcp)

```python
# Broad indexed symbol discovery
mcp__codebase-memory-mcp__search_graph(project="orca-runtime-sensor", label="Function", name_pattern=".*HTTP.*", limit=10)

# Grep-like indexed search
mcp__codebase-memory-mcp__search_code(project="orca-runtime-sensor", pattern="Content-Type", limit=20)

# Architecture and hotspots
mcp__codebase-memory-mcp__get_architecture(project="orca-runtime-sensor", aspects=["packages", "hotspots", "layers"])
```

### Read Code

```python
# Find the qualified name, then read exact source
mcp__codebase-memory-mcp__search_graph(project="orca-runtime-sensor", label="Function", name_pattern=".*ProcessHTTP1Data.*", limit=5)
mcp__codebase-memory-mcp__get_code_snippet(qualified_name="orca-runtime-sensor.pkg.http.ProcessHTTP1Data")

# Targeted symbol body when Serena path is already known
mcp__serena__find_symbol(name_path_pattern="ProcessHTTP1Data", include_body=True, relative_path="orca-runtime-sensor/pkg/http/protocol.go")
```

### Edit Code — The Golden Loop

1. **Search**: `mcp__codebase-memory-mcp__search_graph(...)` or `search_code(...)`
2. **Read**: `mcp__codebase-memory-mcp__get_code_snippet(...)`
3. **Trace**: `mcp__codebase-memory-mcp__trace_call_path(...)` and `mcp__serena__find_referencing_symbols(...)`
4. **Plan**: TaskCreate with research → implement → verify
5. **Edit**: Serena tools
6. **Verify**: `go test`, `pytest`, or targeted checks

### Bash workflow (RTK)

```bash
# These are transparently rewritten by the Bash hook
git status
git diff
go test ./...
ls -la

# Force raw output when debugging fidelity matters
CLAUDE_RAW=1 git --no-pager diff > /tmp/diff.txt
```

### Edit Tools

```python
mcp__serena__replace_symbol_body(
    name_path="MyType/MyMethod",
    relative_path="orca-runtime-sensor/pkg/http/protocol.go",
    body="..."
)

mcp__serena__replace_content(
    relative_path="orca-runtime-sensor/pkg/http/protocol.go",
    needle="old_text",
    repl="new_text",
    mode="literal"
)
```

### Call Graph

```python
mcp__codebase-memory-mcp__trace_call_path(project="orca-runtime-sensor", function_name="ProcessHTTP1Data", direction="inbound", max_depth=3)
mcp__codebase-memory-mcp__trace_call_path(project="orca-runtime-sensor", function_name="ProcessHTTP1Data", direction="outbound", max_depth=3)
```

### Library Documentation

```python
mcp__docs__search_docs(library="fastapi", query="dependency injection", limit=5)
mcp__docs__fetch_url(url="https://docs.example.com/api")
```

---

## Step 3: Memory Protocol

At session start: `mcp__serena__list_memories()` → read relevant ones.

Use memories for durable local facts. Re-check anything tied to upstream PRs, issues, CI, or releases before acting.

---

## Projects

| Project | Path | Language |
|---------|------|----------|
| orca | ~/src/orca | Python/Django |
| orca-sensor | ~/src/orca-sensor | Go |
| orca-runtime-sensor | ~/src/orca-runtime-sensor | Go+eBPF |
| orca-unified | ~/src | Python+Go (multi-repo) |
| helm-charts | ~/src/helm-charts | YAML |

---

## Verification

Show actual command output before claiming done:
- Python: `pytest <path> -v`
- Go: `go test ./...`
- Lint: `ruff check .` / `golangci-lint run`
