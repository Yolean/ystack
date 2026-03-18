# Y-Script Authoring Guide

Scripts in `bin/` follow the `y-` prefix convention for PATH discoverability via tab completion.
This guide covers conventions for writing new scripts and improving existing ones,
with emphasis on making scripts useful to both humans and AI agents.

The y-* convention spans multiple repositories.
Each repo's `bin/` is added to PATH, and scripts can call each other across repos.

## Quick Reference: Making a Compliant Script

`y-script-lint` validates scripts statically (no execution). To pass all checks:

### Bash

```bash
#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

YHELP='y-example - Bump image tags in kustomization files

Usage: y-example IMAGE TAG PATH [--dry-run]

Arguments:
  IMAGE      Container image name (e.g. yolean/node-kafka)
  TAG        Image tag (e.g. a git commit sha)
  PATH       File or directory to update

Options:
  --dry-run  Show what would change without writing

Environment:
  REGISTRY   Override default registry (default: docker.io)

Dependencies:
  y-crane    Used to resolve image digests
  yq         Used for kustomization.yaml updates

Exit codes:
  0          Success
  1          Missing or invalid arguments
  2          Image not found in registry
'

case "${1:-}" in
  help) echo "$YHELP"; exit 0 ;;
  --help) echo "$YHELP"; exit 0 ;;
esac

# Validate
[ -z "$1" ] && echo "First arg must be an image like yolean/node-kafka" >&2 && exit 1

# Main logic here
```

### Node.js

```javascript
#!/usr/bin/env node

const YHELP = `y-example - One line description

Usage: y-example [options]

Options:
  --output json  Output as JSON (default: human-readable)

Environment:
  MY_VAR         Description (default: value)

Dependencies:
  y-crane        Used to resolve digests (via shell)
`;

if (process.argv[2] === 'help' || process.argv[2] === '--help') {
  console.log(YHELP.trim());
  process.exit(0);
}

// Main logic here
```

### TypeScript

```typescript
#!/usr/bin/env -S node --experimental-strip-types

const YHELP = `y-example - One line description
...same structure as Node.js...
`;

if (process.argv[2] === 'help' || process.argv[2] === '--help') {
  console.log(YHELP.trim());
  process.exit(0);
}
```

### What y-script-lint checks (all static, never executes your script)

| Check | FAIL or WARN | Shell | Node.js | How to pass |
|-------|-------------|-------|---------|-------------|
| Shebang | FAIL | `#!/usr/bin/env bash` or `#!/bin/sh` | `#!/usr/bin/env node` or `*-strip-types` | First line |
| `set -eo pipefail` | FAIL | Required | n/a | Second or third line |
| DEBUG pattern | WARN | `[ -z "$DEBUG" ] \|\| set -x` | n/a | Second line |
| Help handler | WARN | `"$1" = "help"` in case/if | `process.argv` includes `help` | See templates above |
| No `npx` | FAIL | Not in non-comment lines | Not in non-comment lines | Use project deps |
| No `eval` | FAIL | Not in non-comment lines | No `eval(` calls | Avoid eval |
| shellcheck | FAIL | `--severity=error` | n/a | Fix shellcheck errors |

### The help text format

```
y-name - One sentence summary

Usage: y-name [options] ARGS

Arguments:
  ...

Options:
  ...

Environment:
  ...

Dependencies:
  y-other    Why it's needed
  jq         JSON processing

Exit codes:
  0          Success
  1          Usage error
```

**Rules:**
- First line: `y-name - description` (the "index line", used by tooling for discovery)
- `Dependencies:` section lists every y-* command and external tool the script calls
- Print help to stdout, exit 0
- Keep it factual and compact — no ASCII art, no long examples

### The `help` subcommand pattern

New scripts use `help` as a positional subcommand (first argument):

```bash
case "${1:-}" in
  help) echo "$YHELP"; exit 0 ;;
  --help) echo "$YHELP"; exit 0 ;;  # backwards compat
esac
```

```javascript
if (process.argv[2] === 'help' || process.argv[2] === '--help') {
```

This is preferred over `--help`-only because:
- It reads naturally: `y-crane help`, `y-cluster-provision-k3d help`
- It follows the subcommand pattern used by git, docker, kubectl
- The help check happens **before** argument parsing, before prerequisite checks,
  before any side effects — so it always works, even in a sandboxed env
- `--help` is accepted for backwards compatibility but not documented in new scripts

**Existing scripts** use various patterns (`--help`, `-h|--help`, `[[ "$1" =~ help$ ]]`).
`y-script-lint` detects all of these. When touching an existing script, migrate to the
`help` subcommand pattern.

### The YHELP variable pattern

Store help text in a variable named `YHELP` (bash) or `YHELP` (JS/TS const):

```bash
YHELP='y-name - description
...
'
```

```javascript
const YHELP = `y-name - description
...
`;
```

This enables `y-script-lint` to extract the summary and dependencies by reading
the source file — no execution required. The variable name `YHELP` is the convention
that tooling looks for.

## General Conventions

### Header

Every shell script must start with a shebang and standard preamble:

```bash
#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail
```

Use `#!/bin/sh` only for POSIX-portable scripts with no bashisms.

Node.js scripts use `#!/usr/bin/env node`.
TypeScript scripts use `#!/usr/bin/env -S node --experimental-strip-types` (Node 22.6+).

### Structured Output for Agents

When a script's output will be consumed by agents, prefer machine-readable formats:

```bash
# For listing/query commands, support --output json
if [ "$OUTPUT_FORMAT" = "json" ]; then
  echo "{\"image\":\"$IMAGE\",\"digest\":\"$DIGEST\",\"bumped\":$BUMPED_COUNT}"
else
  echo "Got $DIGEST for $IMAGE_URL"
fi
```

- **Token efficiency**: Keep output minimal. Avoid banners, progress bars, repeated info.
- **Dry run**: Mutating commands should support `--dry-run`.
- **Deterministic output**: Same inputs produce same output format.
- **Error output to stderr**: `echo "ERROR: message" >&2`. Structured results go to stdout.

### Naming

- Prefix: `y-` for all scripts (enforced by `y-check-bin-executables-are-named-ydash` in checkit)
- Hierarchical naming: `y-{domain}-{action}` (e.g. `y-cluster-provision-k3d`, `y-image-bump`)
- Wrapper scripts for binaries: `y-{toolname}` (e.g. `y-crane`, `y-kubectl`)
- Keep names descriptive enough that tab-completing `y-cluster-` reveals related commands

### Argument Parsing

Use `--flag=value` style for named parameters. Handle help first, then flags:

```bash
case "${1:-}" in
  help) echo "$YHELP"; exit 0 ;;
  --help) echo "$YHELP"; exit 0 ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --context=*) CTX="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --) shift; break ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
```

Validate required arguments early with clear error messages:

```bash
[ -z "$1" ] && echo "First arg must be an image like yolean/node-kafka" >&2 && exit 1
```

### Exit Codes

| Range | Meaning | Example |
|-------|---------|---------|
| 0 | Success | |
| 1 | Usage error / missing args | Missing required IMAGE arg |
| 2-9 | Domain-specific operational errors | Image not found, registry unreachable |
| 10-19 | Precondition failures | Wrong tool version, missing prerequisite |
| 90-99 | Convention/policy violations | Used by checkit for monorepo policy checks |

### Error Handling

- Use `set -eo pipefail` always
- Send error messages to stderr: `echo "ERROR: message" >&2`
- Use meaningful exit codes (document non-zero codes in help)
- Use `trap cleanup EXIT` when temporary files or state changes need reversal
- Validate prerequisites early: `command -v y-crane >/dev/null || { echo "ERROR: y-crane not found" >&2; exit 1; }`

### Environment Variables

- Document all env vars in help text
- Provide sensible defaults: `[ -z "$REGISTRY" ] && REGISTRY="docker.io"`
- Use `DEBUG` for `set -x` tracing (convention: `[ -z "$DEBUG" ] || set -x`)
- Never require secrets as positional args; use env vars or files

## Shell Practices

- Quote variables: `"$VAR"` not `$VAR` (shellcheck will catch this)
- Use `$(command)` not backticks
- Use `[[ ]]` for complex conditionals, `[ ]` for simple tests
- Declare function-local variables with `local`
- Use `mktemp` for temporary files, clean up with `trap`
- Prefer `printf` over `echo` for portable formatting

### Shellcheck

All shell scripts in `bin/` are linted by `y-script-lint` using `y-shellcheck`.
Current minimum severity: `error`.
Use inline directives sparingly and with justification:

```bash
# shellcheck disable=SC2086 # intentional word splitting for BUILDCTL_OPTS
```

## Node.js Practices

- Use project dependencies only (never `npx`)
- Exit with appropriate codes: `process.exit(1)` for errors
- Write errors to stderr: `console.error("ERROR: ...")`
- For JSON output, use `JSON.stringify(result, null, 2)` for human mode, compact for `--output json`

## Cross-Repo Dependencies

### The $YBIN Pattern (checkit)

Checkit scripts use `YBIN="$(dirname $0)"` and call siblings via `$YBIN/y-other-script`.
This makes dependencies traceable by static analysis (grep for `$YBIN/y-`)
but limits calls to within the same repo's bin/.

### PATH-based calls (ystack, bots)

Ystack and bots scripts call y-* commands via PATH, allowing cross-repo invocation.
This is more flexible but makes dependency tracing harder — the indexer
must scan all repos' bin/ directories to resolve a dependency.

Prefer PATH-based calls for cross-repo dependencies (e.g. checkit calling `y-crane` from ystack).
Use `$YBIN/` only when you specifically need to call a sibling script
and want to avoid PATH ambiguity.

## Discoverability and Indexing

### How y-script-lint discovers help text

`y-script-lint` reads script source files and extracts information statically:

1. **Help handler detection**: Greps for known patterns (`"$1" = "help"`, `--help` in case,
   `process.argv.includes`). Detects existing scripts regardless of which pattern they use.
2. **Summary and dependencies** (planned): Parse the `YHELP` variable from source to extract
   the first line (index line) and `Dependencies:` section without executing the script.

Scripts are never executed during lint. This means:
- Lint is fast (~0.2s per script)
- No side effects, no network requests, no prerequisite checks
- Works on any OS without sandbox concerns
- Works on scripts that require specific env (KUBECONFIG, docker, etc.)

### Dependency Graph Discovery

Two complementary approaches:

**1. Declared dependencies (preferred):**
Parse the `Dependencies:` section from the `YHELP` variable in source.

**2. Static analysis (works on existing scripts without changes):**
Grep script source for `y-*` invocations. For checkit-style `$YBIN/y-*` calls
this is straightforward. For PATH-based calls, look for `y-[a-z]` patterns
that aren't inside comments or strings.

### Agent-Oriented Conventions

When agents use y-* scripts, token cost and parse reliability matter:

1. **Concise help**: Keep help text factual and compact.
2. **Structured errors**: Prefix errors with `ERROR:` so agents can regex-match failures.
3. **JSON mode**: For commands that list or query, support `--output json`.
4. **Idempotency**: Where possible, make scripts safe to re-run. Document when a script is NOT idempotent.
5. **Predictable exit codes**: 0 = success, 1 = usage error, 2+ = domain-specific.
6. **No interactive prompts**: Never prompt for input. Use flags, env vars, or fail with a clear message.
7. **Minimal side effects**: Scripts should do one thing.
