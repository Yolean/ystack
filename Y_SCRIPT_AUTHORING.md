# Y-Script Authoring Guide

Scripts in `bin/` follow the `y-` prefix convention for PATH discoverability via tab completion.
This guide covers conventions for writing new scripts and improving existing ones,
with emphasis on making scripts useful to both humans and AI agents.

The y-* convention spans multiple repos (ystack ~90 scripts, checkit ~152 scripts, bots ~10 scripts).
Each repo's `bin/` is added to PATH, and scripts can call each other across repos.

## General Conventions

### Header

Every script must start with a shebang and standard preamble:

```bash
#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail
```

Use `#!/bin/sh` only for POSIX-portable scripts with no bashisms.

### Help Text (Required)

Every script MUST support `--help` / `-h` and print a structured help block.
The **first line** of help output is used by index scripts for discovery,
so it must be a concise one-line summary of what the script does.

**Migration note**: Existing scripts use inconsistent help triggers:
`[ "$1" = "help" ]`, `--help`, or regex `[[ "$1" =~ help$ ]]`.
New scripts MUST use `--help` / `-h`. When touching existing scripts, migrate to `--help`/`-h`
while keeping `help` (no dashes) as a fallback for backwards compatibility.

```
y-example - Bump image tags in kustomization files

Usage: y-example IMAGE TAG PATH [--dry-run]

Arguments:
  IMAGE      Container image name (e.g. yolean/node-kafka)
  TAG        Image tag (e.g. a git commit sha)
  PATH       File or directory to update

Options:
  --dry-run  Show what would change without writing
  --help     Show this help

Environment:
  REGISTRY   Override default registry (default: docker.io)

Dependencies:
  y-crane    Used to resolve image digests
  yq         Used for kustomization.yaml updates

Exit codes:
  0          Success
  1          Missing or invalid arguments
  2          Image not found in registry
```

Key rules:
- First line: `y-name - One sentence description` (this is the "index line")
- List all positional arguments with descriptions
- List all flags/options
- List environment variables that affect behavior
- List y-* dependencies so tooling can build a dependency graph
- List non-obvious exit codes
- Print help to stdout (not stderr) so it can be piped/parsed
- Exit 0 after printing help

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

Guidelines from [Rewrite your CLI for AI Agents](https://justin.poehnelt.com/posts/rewrite-your-cli-for-ai-agents/):

- **Token efficiency**: Keep output minimal. Agents pay per token of context consumed. Avoid banners, decorative output, progress bars, or repeated information.
- **Field selection**: For commands that return rich data, consider `--fields` to let callers request only what they need.
- **Dry run**: Mutating commands should support `--dry-run` to let agents validate before acting.
- **Deterministic output**: Same inputs should produce same output format. Don't mix human commentary into structured output.
- **Error output to stderr**: Human-readable messages go to stderr. Machine-parseable results go to stdout. This lets agents reliably capture output while still showing errors.

### Naming

- Prefix: `y-` for all scripts (enforced by `y-check-bin-executables-are-named-ydash` in checkit)
- Hierarchical naming: `y-{domain}-{action}` (e.g. `y-cluster-provision-k3d`, `y-image-bump`)
- Wrapper scripts for binaries: `y-{toolname}` (e.g. `y-crane`, `y-kubectl`)
- Keep names descriptive enough that tab-completing `y-cluster-` reveals related commands
- Consistent suffixes for CLI wrappers that wrap versioned binaries: `y-{tool}-v{version}-bin`

### Argument Parsing

Use `--flag=value` style for named parameters. Parse with a while loop:

```bash
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
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

Reserve ranges for consistent meaning across all y-* scripts:

| Range | Meaning | Example |
|-------|---------|---------|
| 0 | Success | |
| 1 | Usage error / missing args | Missing required IMAGE arg |
| 2-9 | Domain-specific operational errors | Image not found, registry unreachable |
| 10-19 | Precondition failures | Wrong tool version, missing prerequisite |
| 90-99 | Convention/policy violations | Used by checkit for monorepo policy checks |

Document non-zero exit codes in the `Exit codes:` section of `--help`.

### Error Handling

- Use `set -eo pipefail` always
- Send error messages to stderr: `echo "ERROR: message" >&2`
- Use meaningful exit codes (document non-zero codes in help)
- Use `trap cleanup EXIT` when temporary files or state changes need reversal
- Validate prerequisites early: `command -v y-crane >/dev/null || { echo "ERROR: y-crane not found" >&2; exit 1; }`

### Environment Variables

- Document all env vars in `--help` output
- Provide sensible defaults: `[ -z "$REGISTRY" ] && REGISTRY="docker.io"`
- Use `DEBUG` for `set -x` tracing (convention: `[ -z "$DEBUG" ] || set -x`)
- Use `DEBUGDEBUG` for extra verbose output in complex scripts
- Never require secrets as positional args; use env vars or files

### Dependencies Section in Help

To enable automated dependency discovery, include a `Dependencies:` section in help output listing every `y-*` command and external tool the script calls:

```
Dependencies:
  y-crane       Resolve image digests
  y-buildctl    Run buildkit builds
  yq            YAML processing
  jq            JSON processing
  git           Version control queries
```

This lets an indexer script parse `--help` output to build a dependency graph across all `y-*` scripts.

## Bash-Specific Conventions

### Script Template

```bash
#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  cat <<'EOF'
y-example - One line description

Usage: y-example [options] ARG

Arguments:
  ARG        Description of argument

Options:
  --dry-run  Preview changes without applying
  -h,--help  Show this help

Environment:
  MY_VAR     Description (default: value)

Dependencies:
  y-crane    Used to resolve digests
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --) shift; break ;;
    -*) echo "Unknown flag: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done

# Validate
[ -z "$1" ] && echo "ARG is required. See --help" >&2 && exit 1

# Main logic here
```

### Shell Practices

- Quote variables: `"$VAR"` not `$VAR` (shellcheck will catch this)
- Use `$(command)` not backticks
- Use `[[ ]]` for complex conditionals, `[ ]` for simple tests
- Declare function-local variables with `local`
- Use `mktemp` for temporary files, clean up with `trap`
- Prefer `printf` over `echo` for portable formatting

### Shellcheck

All bash scripts in `bin/` are linted by `test.sh` using `y-shellcheck`.
Current minimum severity: `error`. Fix all shellcheck warnings at the `warning` level or above.
Use inline directives sparingly and with justification:

```bash
# shellcheck disable=SC2086 # intentional word splitting for BUILDCTL_OPTS
```

## Node.js-Specific Conventions

### Script Template

Use TypeScript with `--experimental-strip-types` (Node 22.6+):

```typescript
#!/usr/bin/env -S node --experimental-strip-types

const HELP = `y-example - One line description

Usage: y-example [options]

Options:
  --output json  Output as JSON (default: human-readable)
  -h, --help     Show this help

Environment:
  MY_VAR         Description (default: value)

Dependencies:
  y-crane        Used to resolve digests (via shell)
`;

if (process.argv.includes('--help') || process.argv.includes('-h')) {
  console.log(HELP.trim());
  process.exit(0);
}

// Main logic here
```

### Node.js Practices

- Use project dependencies only (never `npx`)
- Import types from typed packages (e.g. `@octokit/graphql-schema`)
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

### Recommendation

Prefer PATH-based calls for cross-repo dependencies (e.g. checkit calling `y-crane` from ystack).
Use `$YBIN/` only when you specifically need to call a sibling script
and want to avoid PATH ambiguity.

### Agent Output Modes

Checkit's `y-test-fast` already supports `Y_BUILD_OUTPUT_MODE=agents` for reduced output.
Standardize this pattern: scripts with verbose human output should check for an env var
that switches to minimal, machine-parseable output.

## Discoverability and Indexing

### How index.sh Works

The `index.sh` pattern (piloted in bots) iterates over `bin/*`, calls `--help` on each script, and displays the first line. This relies on:

1. Every script supporting `--help`
2. The first line of help being a meaningful summary
3. Help printing to stdout

### Dependency Graph Discovery

Two complementary approaches:

**1. Declared dependencies (preferred for new scripts):**
Parse the `Dependencies:` section from each script's `--help` output.

**2. Static analysis (works on existing scripts without changes):**
Grep script source for `y-*` invocations. For checkit-style `$YBIN/y-*` calls
this is straightforward. For PATH-based calls, look for `y-[a-z]` patterns
that aren't inside comments or strings.

Both approaches enable:

- Visualizing which scripts depend on which
- Detecting circular dependencies
- Understanding the blast radius of changes to foundational scripts like `y-crane`
- Helping agents understand which scripts to use together
- Identifying cross-repo dependency chains (e.g. checkit → ystack → binary)

### Agent-Oriented Conventions

When agents use y-* scripts, token cost and parse reliability matter:

1. **Concise help**: Keep `--help` output factual and compact. No ASCII art, no examples longer than one line each.
2. **Structured errors**: Prefix errors with `ERROR:` so agents can regex-match failures.
3. **JSON mode**: For commands that list or query, support `--output json` to avoid parsing human-formatted tables.
4. **Idempotency**: Where possible, make scripts safe to re-run. Document when a script is NOT idempotent.
5. **Predictable exit codes**: 0 = success, 1 = usage error, 2+ = domain-specific. Document in help.
6. **No interactive prompts**: Never prompt for input. Use flags, env vars, or fail with a clear message.
7. **Minimal side effects**: Scripts should do one thing. If a script has modes that do very different things, consider splitting it.

## Tooling for Style and Security Checks

### Current: shellcheck via test.sh

`test.sh` runs `y-shellcheck --severity=error` on all shell scripts in `bin/`.

### Recommended Additions

Place these in ystack as scripts or CI steps:

#### y-script-lint (slow, runs in CI or on demand)

Scans a repo's `bin/` directory, executes `--help` on each y-* script,
and validates convention alignment. Writes results to a dotfile
that `y-script-index` can read without re-executing anything.

**Two-phase approach — static checks never execute the script:**

Phase 1 (static, safe): Read the script source and check:
- Shebang present and recognized (`bash`, `sh`, `node`)
- Standard header (`set -eo pipefail`, DEBUG pattern)
- Contains a help handler (recognizable `--help` / `-h` in a case/if pattern)
- No use of `npx`
- No `eval` on user input

Scripts that fail phase 1 are recorded with `"help": false` and **never executed**.

Phase 2 (sandboxed execution): For scripts that pass static screening,
run `--help` in a sandbox to extract the summary and declared dependencies:

```bash
env -i \
  PATH="$PATH" \
  HOME="$(mktemp -d)" \
  timeout 5 \
  /bin/bash -c 'cd "$(mktemp -d)" && exec "$@"' _ "$script" --help
```

Sandbox properties:
- **Stripped env**: `env -i` clears credentials, cloud auth, KUBECONFIG etc.
  Only PATH is preserved (needed to resolve y-* dependencies in help code).
- **Temp HOME**: Prevents reading credentials, ssh keys, cloud config files.
- **Temp working dir**: Prevents writes to the repo.
- **Timeout 5s**: Kills scripts that hang or do real work on `--help`.
- **No network** (Linux bots): Wrap with `unshare --net` where available.

**Checks from the sandboxed run:**
- Exits 0 and produces output to stdout
- First help line matches `y-name - description` format
- `Dependencies:` section exists in help output

**Output:** Writes `.y-script-lint.json` in the repo's `bin/` directory:

```json
{
  "generated": "2026-03-14T12:00:00Z",
  "scripts": {
    "y-crane": {
      "summary": "Crane binary wrapper for container image operations",
      "dependencies": ["y-bin-download"],
      "checks": {"help": true, "header": true, "deps_declared": true}
    },
    "y-build": {
      "summary": null,
      "dependencies": [],
      "checks": {"help": false, "header": true, "deps_declared": false},
      "errors": ["no --help support", "no Dependencies section"]
    }
  }
}
```

Scripts that fail the `help` check are included with `"summary": null`
so the lint result doubles as a backfill TODO list.

The dotfile should be gitignored — it's a local cache, not source of truth.

#### y-script-index (fast, safe for agents)

Reads `.y-script-lint.json` from one or more repo `bin/` directories.
**Does not execute any scripts.** Only lists scripts that passed lint checks.

```bash
# Human-friendly table (default)
y-script-index
  # Last lint: 2026-03-14T12:00:00Z (2 hours ago)
  # 187/252 scripts passed, 65 need --help backfill
  y-crane                             Crane binary wrapper for container image operations
  y-cluster-provision-k3d             Provision a k3d cluster with ystack defaults
  ...

# JSON for agents
y-script-index --output json

# Dependency graph (dot format, pipe to graphviz)
y-script-index --deps
y-script-index --deps --output dot | dot -Tsvg -o deps.svg

# Filter by domain
y-script-index --filter cluster

# Show stale lint warning (e.g. if scripts changed since last lint)
y-script-index
  # Last lint: 2026-03-12T09:00:00Z (2 days ago)
  # WARNING: 3 scripts modified since last lint run. Run y-script-lint to update.
```

The header always shows when lint was last run and how many scripts passed.
If any script's mtime is newer than the dotfile, a warning is printed.
This lets developers and agents judge how trustworthy the index is.

Because it only reads a dotfile, agents can call `y-script-index` freely
to discover available tools without risk of side effects or slow execution.

**Multi-repo support:** By default, scans `bin/.y-script-lint.json` in known
repo roots (ystack, checkit, bots). Accepts `--path` to override.

#### Security checks (extend test.sh or run separately)

- `shellcheck --severity=warning` (raise the bar from current `error`)
- Check for unquoted variables in file paths
- Check for `eval` usage (flag for review)
- Check that secrets come from env vars or files, never positional args
- Verify `trap cleanup EXIT` when `mktemp` is used
- osv-scanner for Node.js dependency vulnerabilities (already in y-bin.optional.yaml)
