package converge_ystack

import (
	"list"
	"strings"
	"tool/cli"
	"tool/exec"
)

_context:    string @tag(context)
_path:       string @tag(path)
_kubeconfig: *"" | string @tag(kubeconfig)
_overrideIP: *"" | string @tag(overrideIP)

_env: {
	CONTEXT:     _context
	PATH:        _path
	OVERRIDE_IP: _overrideIP
	if _kubeconfig != "" {
		KUBECONFIG: _kubeconfig
	}
}

_activeSteps: [for s in steps if s.enabled {s}]

// Build human-readable plan
_planLines: [for s in _activeSteps {
	let _nsLabel = {
		if s.namespace != _|_ {" [ns: \(s.namespace)]"}
		if s.namespace == _|_ {""}
	}
	let _header = "  \(s.kustomization)\(_nsLabel)"
	let _actionLines = [for a in s.actions {"    action: \(a.description)"}]
	let _checkLines = [for c in s.checks {
		if c.kind == "wait" {"    check:  wait \(c.resource) \(c.for)"}
		if c.kind == "rollout" {"    check:  rollout \(c.resource)"}
		if c.kind == "exec" {"    check:  \(c.description)"}
	}]
	strings.Join(list.Concat([[_header], _actionLines, _checkLines]), "\n")
}]

_plan: strings.Join(list.Concat([
	["=== Converge plan (context=\(_context)) ==="],
	["Steps (\(len(_activeSteps))):"],
	_planLines,
	["==="],
]), "\n")

// Generate shell commands per step, wrapped in error handler
_stepCmds: [for s in _activeSteps {
	let _apply = "kubectl-yconverge --context=\(_context) --skip-checks -k \(s.kustomization)/"
	let _actionCmds = [for a in s.actions {"echo '  action: \(a.description)' && " + a.command}]
	let _checkCmds = [for c in s.checks {
		if c.kind == "wait" {
			let _ns = {
				if c.namespace != _|_ {"-n \(c.namespace) "}
				if c.namespace == _|_ {""}
			}
			"echo '  check: wait \(c.resource)' && kubectl --context=\(_context) wait --for=\(c.for) --timeout=\(c.timeout) \(_ns)\(c.resource)"
		}
		if c.kind == "rollout" {
			let _ns = {
				if c.namespace != _|_ {"-n \(c.namespace) "}
				if c.namespace == _|_ {""}
			}
			"echo '  check: rollout \(c.resource)' && kubectl --context=\(_context) rollout status --timeout=\(c.timeout) \(_ns)\(c.resource)"
		}
		if c.kind == "exec" {"echo '  check: \(c.description)' && { for _retry_i in $(seq 1 15); do " + c.command + " && break || sleep 2; done; }"}
	}]
	let _body = strings.Join(list.Concat([[_apply], _actionCmds, _checkCmds]), "\n")
	"echo '>>> \(s.kustomization)'\nif ! (\n\(_body)\n); then\n  echo ''\n  echo \"FAILED: \(s.kustomization)\"\n  echo 'The step above failed. Re-run to retry from this point.'\n  exit 1\nfi"
}]

_script: strings.Join(list.Concat([
	["set -eo pipefail"],
	_stepCmds,
	["echo '=== Converge complete ==='"],
]), "\n")

// Write script to temp file so CUE error messages don't dump the entire script
command: converge: {
	printPlan: cli.Print & {
		text: _plan
	}

	writeScript: exec.Run & {
		$after: printPlan
		cmd: ["sh", "-c", "SCRIPT=$(mktemp /tmp/ystack-converge.XXXXXX.sh) && cat > $SCRIPT && echo $SCRIPT"]
		stdin: _script
		stdout: string
	}

	run: exec.Run & {
		$after: writeScript
		cmd: ["sh", "-c", "sh " + strings.TrimSpace(writeScript.stdout) + "; EXIT=$?; rm -f " + strings.TrimSpace(writeScript.stdout) + "; exit $EXIT"]
		env: _env
	}
}
