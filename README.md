# agent-substrate-demo

![lint](https://github.com/platformfix/agent-substrate-demo/actions/workflows/lint.yml/badge.svg)
![commit-lint](https://github.com/platformfix/agent-substrate-demo/actions/workflows/commit-lint.yaml/badge.svg)
![pr-lint](https://github.com/platformfix/agent-substrate-demo/actions/workflows/pr-lint.yml/badge.svg)
![e2e](https://github.com/platformfix/agent-substrate-demo/actions/workflows/e2e.yml/badge.svg)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/platformfix/agent-substrate-demo/badge)](https://securityscorecards.dev/viewer/?uri=github.com/platformfix/agent-substrate-demo)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A fully local, scripted conference demo of [Agent Substrate](https://github.com/agent-substrate/substrate)'s
request-parking behavior under `WorkerPool` saturation - no slides pretending
to show output that was never actually run.

## Why this exists

Most of an AI agent's runtime life is spent waiting, not computing, and a
Kubernetes scheduler built around request/limit and pod scheduling was never
designed to price that kind of waiting. Agent Substrate's answer is to
multiplex many agents across a small pool of workers, suspending an idle
agent's sandbox and resuming it later rather than holding a worker for the
whole conversation. When every worker is busy, a new request doesn't just
fail - it *parks*: it waits, within a budget, for a worker to free up, then
resumes normally.

That's a genuinely new failure mode for a platform engineer to reason about,
and the only way to show it honestly on stage is against a real cluster - not
a diagram. This repo makes that fully local and disposable: one `./setup.sh`
in the green room stands up a throwaway `kind` cluster with Agent Substrate
installed, and every other script talks only to that cluster, never your
default kubeconfig or context.

## The scenario

A `WorkerPool` named `parking` is sized to exactly **two workers**. Four
actors (`p1`-`p4`) share it:

1. `p1` and `p2` start first and fill both workers (`ACTOR_STATE_RUNNING`).
2. `p3` requests a worker while the pool is full. Instead of failing
   immediately, the request **parks** - it waits, and as soon as `p1` is
   suspended (freeing its worker) within the park budget, `p3`'s request
   resumes and completes normally.
3. The same saturation is then repeated with parking turned off
   (`--parked-request-max=0` patched onto `atenet-router`). `p4`'s request
   under identical load gets a real `503` instead of a wait - the same
   saturation, a genuinely different outcome, depending on one flag.

`preflight.sh` proves both outcomes for real, immediately before you walk on
stage, then restores the baseline `demo.sh` expects.

## Quick start

```bash
./setup.sh      # once, in the green room - vendors Substrate, creates the kind cluster, installs everything
./preflight.sh  # immediately before you walk on stage - proves both outcomes for real
./demo.sh       # on stage (DEMO_AUTO_RUN=1 DEMO_RUN_FAST=1 to run it non-interactively, as CI does)
./reset.sh      # between rehearsal passes - see "Rehearsing" below before running demo.sh again
./cleanup.sh    # after the conference - deletes the kind cluster and its registry
```

`env.sh` and `util.sh` are shared config and harness code, sourced by the
scripts above - nothing to run directly.

## Rehearsing: always `reset.sh` before the next `demo.sh`

`demo.sh` patches `atenet-router` to disable parking (`--parked-request-max=0`)
partway through, so it can show the `503` failure - but `demo.sh` itself never
undoes that patch; only `preflight.sh` and `reset.sh` do, via
`kubectl rollout undo`. Between rehearsal passes, the sequence is always
`./reset.sh` then `./demo.sh` - **never `./demo.sh` twice in a row without a
`reset.sh` in between.**

If you do run `demo.sh` twice back-to-back, the patch is applied a second
time, stacking a second `--parked-request-max=0` onto the deployment's args.
A single `rollout undo` (what `reset.sh` runs) only unwinds one of those two
stacked revisions, so parking is left disabled even after a reset that looks
like it succeeded. If that ever happens, `kubectl -n ate-system rollout undo
deployment/atenet-router` a second time clears it, or just `./cleanup.sh` and
`./setup.sh` again for a guaranteed-clean baseline.

## Why gVisor, not a microVM

Agent Substrate can sandbox a worker with either gVisor or a microVM (e.g.
Firecracker-class) isolation. A microVM needs hardware virtualization
(`/dev/kvm`) passed through to the container running it - `setup.sh` probes
for it and disables microVM support when it isn't there:

```
Probing for /dev/kvm in the Docker environment...
/dev/kvm not available: micro-VM support disabled (gVisor still works).
```

Neither GitHub Actions' `ubuntu-latest` runners nor Docker Desktop on macOS
expose `/dev/kvm` by default, so this demo runs entirely on the gVisor
(`SANDBOX_CLASS_GVISOR`) sandbox class - it needs no nested virtualization
and works the same in CI, on a laptop, and in the green room.

## Why the Substrate pin exists, and how to bump it

`env.sh` pins an exact commit SHA, not a branch or tag:

```bash
export SUBSTRATE_SHA="27bf34444e0c1a8762aebcafbc733a97c023cb4d"
```

Agent Substrate is pre-1.0 and says so itself - its own README describes it
as not ready for production use, with APIs "almost guaranteed to change."
Tracking a moving branch would mean this demo could silently break, or
silently change behavior, on a day it's about to go on stage. Pinning to one
tested commit means the demo only changes when someone deliberately changes
it.

Bumping the pin is a deliberate, separately-tested action, not a routine
update:

1. Update `SUBSTRATE_SHA` in `env.sh` to the new commit.
2. Remove the vendored checkout so `setup.sh` re-clones at the new SHA:
   `rm -rf .vendor/substrate`.
3. Run the full lifecycle (`setup.sh` -> `preflight.sh` -> `demo.sh` ->
   `reset.sh` -> `cleanup.sh`) locally and confirm every step still passes
   before committing the bump - `preflight.sh`'s two `PASS` assertions are
   what actually prove parking behavior didn't regress upstream.

## Security and supply chain

Every GitHub Action in this repo's workflows is pinned to a commit SHA, not
a floating tag. Dependabot watches the `github-actions` ecosystem weekly
(`.github/dependabot.yml`). Commit messages and pull request titles are both
enforced as [Conventional Commits](https://www.conventionalcommits.org/) in
CI (`commit-lint`, `pr-lint`) - see [`CONTRIBUTING.md`](CONTRIBUTING.md). A
weekly [OpenSSF Scorecard](https://securityscorecards.dev/) scan runs against
`main`. `e2e.yml` runs this repo's own full lifecycle - `setup` ->
`preflight` -> `demo` -> `reset` -> `cleanup` - against a real `kind` cluster
on every push and pull request, so a regression in the scripts themselves
fails CI, not just a slide. See [`SECURITY.md`](SECURITY.md) for how to
report a vulnerability.

## Output, verified (2026-09-19)

The full fresh lifecycle below was run end to end on 2026-09-19, exactly as
CI runs it (`./setup.sh` -> `./preflight.sh` ->
`DEMO_AUTO_RUN=1 DEMO_RUN_FAST=1 ./demo.sh` -> `./reset.sh` ->
`./cleanup.sh`), starting from no cluster. All five steps passed.

**`./setup.sh`** - vendored Substrate at the pinned SHA, created the `kind`
cluster, installed Agent Substrate (gVisor sandbox class, microVM disabled -
no `/dev/kvm`), deployed the `parking` `WorkerPool`, and built `kubectl-ate`:

```
==> Setup complete. Run ./preflight.sh immediately before you walk on stage.
```

**`./preflight.sh`** - created `p1`-`p4`, filled the two-worker pool, and
proved both outcomes for real:

```
==> Proving a parked request resolves (p3, while p1 suspends within budget)
    PASS: parked request resolved with 200
==> Proving a request fails fast with parking disabled (p4)
    PASS: request failed fast with 503 (parking off)

==> PREFLIGHT PASSED. Cluster is in the baseline state demo.sh expects.
```

**`DEMO_AUTO_RUN=1 DEMO_RUN_FAST=1 ./demo.sh`** - the on-stage script, run
non-interactively:

```
curl -s -w '\n-> HTTP %{http_code} in %{time_total}s\n' -H 'ate-target-actor: ate-demo-parking/p3' http://localhost:8000
hello from: 169.254.17.2 | preserved memory count: 2 | preserved file counter: -1

-> HTTP 200 in 2.216603s
```

`p3` parked while `p1` was suspended, then resolved with a `200` two seconds
later. With parking then patched off, `p4`'s request against identical
saturation failed as expected (`curl -sf` exits non-zero on the `503`; the
script's own `run_expect_fail` check - which flags loudly if the command
unexpectedly *succeeds* - raised nothing).

**`./reset.sh`** - restored parking with a single `rollout undo` (valid here
because `demo.sh` had been run exactly once - see "Rehearsing" above) and
suspended all four actors:

```
==> Reset complete.
```

**`./cleanup.sh`** - deleted the `kind` cluster and its local registry.

## License

MIT - see [`LICENSE`](LICENSE).
