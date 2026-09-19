# Security Policy

## Supported versions

agent-substrate-demo has no releases or long-term-support branch to track - it's a single scripted demo kept working against `main`.

## Reporting a vulnerability

Please report security issues privately rather than opening a public GitHub issue: use [GitHub's private vulnerability reporting](https://github.com/platformfix/agent-substrate-demo/security/advisories/new) for this repository (Security tab -> Report a vulnerability).

Include what you'd include in any good bug report: the affected commit, what you found, and how to reproduce it. We'll acknowledge new reports within 5 business days and aim to have a fix or mitigation plan within 30 days, depending on severity.

## Scope

This repo stands up a local, disposable `kind` cluster and installs a pinned upstream [Agent Substrate](https://github.com/agent-substrate/substrate) checkout at the commit SHA pinned in `env.sh` - that's the intended design for a local, throwaway demo cluster, not a finding on its own. Reports about the setup/teardown scripts (`setup.sh`, `preflight.sh`, `demo.sh`, `reset.sh`, `cleanup.sh`), the pinned vendoring mechanism, or the CI pipeline are in scope.
