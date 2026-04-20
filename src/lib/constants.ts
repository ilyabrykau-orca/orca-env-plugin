import { homedir } from "os";

export const HOME = homedir();
export const SRC_PREFIX = `${HOME}/src/`;
export const CLAUDE_PREFIX = `${HOME}/.claude/`;
export const LOG_DIR = `${HOME}/.claude/logs`;
export const LOG_FILE = `${LOG_DIR}/hooks.jsonl`;
export const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT ?? "";

export const SOURCE_EXTS = new Set([
  "go", "ts", "tsx", "js", "jsx", "rs", "py",
  "c", "cc", "cpp", "h", "hpp",
  "rb", "java", "kt", "php", "scala", "swift",
]);

export const ALLOWED_EXTS = new Set([
  "md", "txt", "rst", "json", "yaml", "yml", "toml", "ini", "cfg", "conf",
  "sh", "bash", "zsh", "fish",
  "env", "lock", "sum", "mod",
  "csv", "svg", "png", "jpg", "gif", "ico",
  "html", "css", "scss", "less",
  "xml", "xsd", "proto", "tmpl", "tpl",
  "hcl", "tf", "tfvars",
  "sql", "graphql", "gql",
  "log", "out", "pid", "sock",
  "patch", "diff",
]);

export const ALLOWED_FILENAME_PREFIXES = [
  "README", "LICENSE", "CHANGELOG", "CONTRIBUTING",
  "Makefile", "Dockerfile", "docker-compose",
  "Taskfile", "Justfile", "Vagrantfile", "Brewfile",
  "Gemfile", "Procfile",
  ".gitignore", ".gitattributes", ".dockerignore",
  ".editorconfig", ".prettierrc", ".eslintrc", ".golangci", ".goreleaser",
  "go.mod", "go.sum",
  "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
  "Cargo.toml", "Cargo.lock",
  "pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "poetry.lock",
  "tsconfig",
  "jest.config", "vite.config", "webpack.config", "rollup.config", "babel.config",
];

export const ALLOWED_PATH_COMPONENTS = [
  "/docs/", "/doc/", "/documentation/",
  "/generated/", "/gen/",
  "/vendor/", "/node_modules/",
  "/testdata/", "/test_data/", "/fixtures/",
  "/.github/", "/.vscode/", "/.idea/",
  "/scripts/", "/hack/",
  "/deploy/", "/chart/", "/charts/", "/templates/",
];

export const SERENA_EDIT_TOOLS = new Set([
  "mcp__serena__replace_symbol_body",
  "mcp__serena__replace_content",
  "mcp__serena__insert_after_symbol",
  "mcp__serena__insert_before_symbol",
  "mcp__serena__rename_symbol",
  "mcp__serena__safe_delete_symbol",
]);

export const NATIVE_FILE_TOOLS = new Set([
  "Read", "Edit", "Write", "Grep", "Glob", "Search",
]);

export const PROJECT_MAP: Record<string, string> = {
  "orca-env-plugin": "orca-env-plugin",
  "orca-cloud-platform": "orca-cloud-platform",
  "orca-runtime-sensor": "orca-runtime-sensor",
  "orca-sensor": "orca-sensor",
  "helm-charts": "helm-charts",
  "grafana-provisioning": "grafana-provisioning",
};

