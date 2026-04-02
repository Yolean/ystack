package converge_ystack

import (
	"list"
	"strings"
	"tool/cli"
	"tool/exec"
)

_context: string @tag(context)
_dryRun:  *"false" | "true" @tag(dryRun)
_diff:    *"false" | "true" @tag(diff)
_path:       string @tag(path)
_kubeconfig: *"" | string @tag(kubeconfig)

_env: {
	CONTEXT:    _context
	PATH:       _path
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
	["=== Converge plan (context=\(_context), dry-run=\(_dryRun), diff=\(_diff)) ==="],
	["Steps (\(len(_activeSteps))):"],
	_planLines,
	["==="],
]), "\n")

command: converge: {
	printPlan: cli.Print & {
		text: _plan
	}

	for i, s in _activeSteps {
		let _name = strings.Replace(strings.Replace(s.kustomization, "k3s/", "", 1), "/", "_", -1)

		// Apply via kubectl-yconverge
		"apply_\(_name)": exec.Run & {
			$after: printPlan
			cmd: ["kubectl-yconverge", "--context=\(_context)", "-k", "\(s.kustomization)/"]
			env: _env
			stdout: string
		}

		// Actions (run after apply)
		for j, a in s.actions {
			"action_\(_name)_\(j)": exec.Run & {
				$after: "apply_\(_name)"
				cmd: ["sh", "-c", a.command]
				env: _env
			}
		}

		// Checks (run after actions or apply)
		for j, c in s.checks {
			let _afterTarget = {
				if len(s.actions) > 0 {"action_\(_name)_\(len(s.actions) - 1)"}
				if len(s.actions) == 0 {"apply_\(_name)"}
			}
			"check_\(_name)_\(j)": exec.Run & {
				$after: _afterTarget
				if c.kind == "wait" {
					let _nsFlag = {
						if c.namespace != _|_ {"-n \(c.namespace) "}
						if c.namespace == _|_ {""}
					}
					cmd: ["sh", "-c", "kubectl --context=\(_context) wait --for=\(c.for) --timeout=\(c.timeout) \(_nsFlag)\(c.resource)"]
				}
				if c.kind == "rollout" {
					let _nsFlag = {
						if c.namespace != _|_ {"-n \(c.namespace) "}
						if c.namespace == _|_ {""}
					}
					cmd: ["sh", "-c", "kubectl --context=\(_context) rollout status --timeout=\(c.timeout) \(_nsFlag)\(c.resource)"]
				}
				if c.kind == "exec" {
					cmd: ["sh", "-c", c.command]
				}
				env: _env
			}
		}
	}
}
