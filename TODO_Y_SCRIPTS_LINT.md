# TODO: y-* Script Lint and Index Tooling

Implementation plan for `y-script-lint` and `y-script-index`,
designed to make ~250 y-* scripts across three repos discoverable and convention-aligned.

See Y_SCRIPT_AUTHORING.md for the conventions these tools enforce.

## Current State

### What we have

| Repo | Scripts | Shell lint | JS/TS lint | Help coverage |
|------|---------|-----------|------------|---------------|
| ystack | ~90 | shellcheck 0.11.0 via test.sh, `--severity=error` | none | ~6 scripts |
| checkit | ~152 | none | legacy `.eslintrc` in bin/ (outdated) | inconsistent |
| bots | ~10 | none | eslint 9 in repo root (not targeting bin/) | good (index.sh pilot) |

### Script languages in bin/ directories

| Language | Shebang pattern | Count | Current lint |
|----------|----------------|-------|-------------|
| bash | `#!/usr/bin/env bash` | ~130 | shellcheck (ystack only) |
| sh | `#!/bin/sh` | ~40 | shellcheck (ystack only) |
| Node.js | `#!/usr/bin/env node` | ~17 | none |
| TypeScript | `#!/usr/bin/env -S node --experimental-strip-types` | ~7 | none |
| JS libraries | no shebang, `require`d by other scripts | ~3 | none |
| YAML config | `#!/usr/bin/env y-bin-download` | 2 | n/a (not scripts) |
| Python | `#!/usr/bin/env python3` | 1 | none |

### Gaps

1. **checkit and bots have no shellcheck at all** — 160+ shell scripts unlinted
2. **~20 Node.js/TypeScript scripts have no lint** — these are exactly the kind
   that benefit most from lint (type safety, security rules)
3. **Help text is inconsistent** — `help` vs `--help` vs regex, stdout vs stderr
4. **No dependency tracking** between scripts
5. **bots index.sh** executes every script's `--help` with no sandboxing

### Shared eslint infrastructure

`eslint-config-y` already exists at `checkit/y-dev/eslint-config-y/` with profiles:
`lib`, `node`, `reactFrontend`, `nextJs`, `mocha`, `vitest`, `storybook`.

No `bin` profile exists for CLI scripts.

## Implementation Plan

### Step 1: Add `bin` profile to eslint-config-y

Location: `checkit/y-dev/eslint-config-y/private/bin.js`

Purpose: Shared rules for y-* Node.js/TypeScript scripts in `bin/` directories.

```js
import js from '@eslint/js';
import stylistic from '@stylistic/eslint-plugin';

export default [
  js.configs.recommended,
  {
    plugins: { '@stylistic': stylistic },
    rules: {
      // CLI scripts write to stdout/stderr by design
      'no-console': 'off',
      // Scripts use exit codes deliberately
      'no-process-exit': 'off',
      // Security: no eval in scripts that may handle untrusted input
      'no-eval': 'error',
      'no-implied-eval': 'error',
      // Inherit stylistic rules from the shared config
      '@stylistic/semi': ['error', 'always'],
      '@stylistic/indent': ['error', 2],
    },
  },
];
```

Export from `checkit/y-dev/eslint-config-y/index.js` as `bin`.

For TypeScript support, add `typescript-eslint` as an optional peer dep.
Bots already has it; checkit can add it when ready.

Repos consume it via `bin/eslint.config.js`:

```js
import config from 'eslint-config-y';
export default [...config.bin, { files: ['y-*.js', 'y-*.ts', '*.ts'] }];
```

This replaces the legacy `checkit/bin/.eslintrc`.

### Step 2: Extend shellcheck to checkit and bots

Both repos need shell linting. Two approaches:

**Option A**: Each repo gets its own test.sh calling y-shellcheck (copy ystack's pattern).

**Option B** (preferred): y-script-lint handles shellcheck as part of its static phase,
so there's one tool that lints both shell and JS/TS scripts uniformly.

y-script-lint would invoke:
- `y-shellcheck --severity=error` for `#!/bin/sh` and `#!/usr/bin/env bash` scripts
- `eslint` via the repo's `bin/eslint.config.js` for Node.js/TypeScript scripts

This means repos only need to wire up one lint command, not two.

### Step 3: Implement y-script-lint

Location: `ystack/bin/y-script-lint`
Language: bash (it orchestrates other tools; keeping it in bash avoids bootstrapping issues)

#### Phase 1: Static analysis (no execution)

For each y-* file in the target `bin/` directory:

1. **Detect language** from shebang:
   - `*sh` -> shell script
   - `*node*` -> Node.js/TypeScript
   - `*y-bin-download` -> skip (YAML config, not a script)
   - no shebang + `.js`/`.ts` extension -> JS library (note but skip execution)

2. **Shell scripts** — static checks:
   - Has `set -e` or `set -eo pipefail`
   - Has `[ -z "$DEBUG" ] || set -x` pattern
   - Contains help handler: grep for `--help\|help` in `case` or `if` blocks
   - Run `y-shellcheck --severity=error` on the file
   - No `npx` usage
   - No unguarded `eval`

3. **Node.js/TypeScript scripts** — static checks:
   - Contains help handler: `process.argv.includes('--help')`
   - Run `eslint` if `bin/eslint.config.js` exists
   - No `npx` usage
   - No `eval()` calls

4. **Record results** for each script:
   - `language`: shell/node/typescript/library/config
   - `checks`: object with boolean per check
   - `errors`: list of failures
   - `has_help_handler`: boolean (gates phase 2)

#### Phase 2: Sandboxed --help execution

Only for scripts where `has_help_handler` is true from phase 1.

```bash
sandbox_help() {
  local script="$1"
  local tmpdir
  tmpdir=$(mktemp -d)

  local sandbox_cmd=(env -i PATH="$PATH" HOME="$tmpdir" timeout 5)

  # Linux bots: add network isolation
  if command -v unshare >/dev/null 2>&1; then
    sandbox_cmd=(unshare --net "${sandbox_cmd[@]}")
  fi

  "${sandbox_cmd[@]}" /bin/bash -c 'cd "$(mktemp -d)" && exec "$@"' _ "$script" --help 2>/dev/null

  rm -rf "$tmpdir"
}
```

Parse the help output:
- First line -> `summary` (validate format: `y-name - description`)
- Lines after `Dependencies:` -> `dependencies` array
- Lines after `Exit codes:` -> `exit_codes` object

#### Output: .y-script-lint.json

Written to the target repo's `bin/` directory. Gitignored.

```json
{
  "generated": "2026-03-15T10:00:00Z",
  "tool_version": "1",
  "directory": "/Users/bot1/Yolean/ystack/bin",
  "stats": {
    "total": 90,
    "passed": 42,
    "failed_static": 38,
    "failed_help": 10,
    "skipped": 2
  },
  "scripts": {
    "y-crane": {
      "language": "shell",
      "summary": "Crane binary wrapper for container image operations",
      "dependencies": ["y-bin-download"],
      "checks": {
        "shebang": true,
        "header": true,
        "help_handler": true,
        "help_runs": true,
        "help_format": true,
        "deps_declared": true,
        "shellcheck": true,
        "no_npx": true,
        "no_eval": true
      }
    },
    "y-build": {
      "language": "shell",
      "summary": null,
      "dependencies": [],
      "checks": {
        "shebang": true,
        "header": true,
        "help_handler": false,
        "help_runs": null,
        "help_format": null,
        "deps_declared": false,
        "shellcheck": true,
        "no_npx": true,
        "no_eval": true
      },
      "errors": ["no help handler found in source"]
    },
    "y-monorepo-build-prepare": {
      "language": "node",
      "summary": "Prepare monorepo packages for Docker builds",
      "dependencies": [],
      "checks": {
        "shebang": true,
        "help_handler": true,
        "help_runs": true,
        "help_format": true,
        "deps_declared": false,
        "eslint": true,
        "no_npx": true,
        "no_eval": true
      },
      "errors": ["no Dependencies section in help output"]
    }
  }
}
```

`null` check values mean the check was skipped (e.g. help_runs is null when help_handler is false).

### Step 4: Implement y-script-index

Location: `ystack/bin/y-script-index`
Language: bash

Reads `.y-script-lint.json` files. Never executes scripts.

```
y-script-index --help

y-script-index - List y-* scripts that passed lint checks

Usage: y-script-index [options]

Options:
  --output json    Output as JSON (default: human-readable table)
  --output dot     Output dependency graph in Graphviz dot format
  --deps           Include dependency information
  --filter DOMAIN  Only show scripts matching y-DOMAIN-*
  --all            Include scripts that failed lint (marked with !)
  --path DIR       Scan specific directory (default: known repo bin/ dirs)
  -h, --help       Show this help

Environment:
  YOLEAN_HOME      Workspace root (default: ~/Yolean)

Dependencies:
  jq               Parse .y-script-lint.json files
```

Behavior:
- Discovers `.y-script-lint.json` in `$YOLEAN_HOME/{ystack,checkit,bots}/bin/`
- Prints header with lint timestamp and staleness check (compare dotfile mtime to script mtimes)
- Lists only scripts where all checks passed (or `--all` to show everything)
- `--output json` emits a merged index across repos (agent-friendly)
- `--deps` adds a dependency column or section
- `--output dot` renders the dependency graph

#### Staleness detection

```bash
lint_file="$bin_dir/.y-script-lint.json"
lint_mtime=$(stat -f %m "$lint_file" 2>/dev/null || stat -c %Y "$lint_file" 2>/dev/null)
stale_count=0
for script in "$bin_dir"/y-*; do
  script_mtime=$(stat -f %m "$script" 2>/dev/null || stat -c %Y "$script" 2>/dev/null)
  [ "$script_mtime" -gt "$lint_mtime" ] && stale_count=$((stale_count + 1))
done
```

### Step 5: Wire up CI

#### ystack test.sh

Keep existing shellcheck invocation. Add:

```bash
y-script-lint --check bin/
```

`--check` mode: exit non-zero if any script fails static checks (phase 1).
Does NOT require the dotfile to exist — it's a CI gate, not an index builder.

#### checkit

Add to the turbo `lint` pipeline or a new top-level test:

```bash
y-script-lint --check bin/
```

#### bots

Same pattern. Also replace the unsandboxed `index.sh` with:

```bash
y-script-lint bin/
# index.sh can then read .y-script-lint.json instead of executing --help
```

## Open Questions

1. **Severity levels for y-script-lint**: Should missing `--help` be a warning or error?
   Starting as warning makes sense — it lets CI pass while we backfill.
   Use `--strict` to treat warnings as errors once coverage is high enough.

2. **eslint-config-y as a dependency for ystack**: ystack has no npm setup currently.
   Options: (a) ystack only runs shellcheck, eslint runs in repos that have npm,
   (b) add a minimal package.json to ystack.
   Recommend (a) — keep ystack npm-free; y-script-lint delegates eslint to repos that have it.

3. **y-bin-download YAML files**: These have shebangs but aren't scripts.
   y-script-lint should detect the `y-bin-download` shebang and skip them
   (category: `config`, not `shell`).

4. **Backfill priority**: Which of the ~200 scripts without `--help` to fix first?
   Suggest: scripts that agents actually use > scripts in active development >
   stable infrastructure scripts > legacy/deprecated scripts.
   y-script-lint's `--all` output serves as the backfill TODO list.

## Dependency Summary

```
y-script-lint
├── y-shellcheck (for shell scripts)
├── eslint (for Node.js/TS scripts, only if bin/eslint.config.js exists)
├── jq (to write .y-script-lint.json)
├── stat, mktemp, timeout (POSIX)
└── unshare (optional, Linux only, for network sandbox)

y-script-index
└── jq (to read .y-script-lint.json)

eslint-config-y (bin profile)
├── @eslint/js
├── @stylistic/eslint-plugin
└── typescript-eslint (optional peer dep)
```
