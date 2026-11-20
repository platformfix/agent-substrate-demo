#!/usr/bin/env bash
# Single place to change identifiers - never touched by demo.sh itself.
# Pattern: platformfix/k8s-ai-demo's env.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

export CLUSTER_NAME="agent-substrate-demo"
# .github/workflows/e2e.yml hardcodes this same port in its KO_DOCKER_REPO
# env var (localhost:5001) - update both together if this ever changes.
export KIND_REGISTRY_PORT="5001"

# Pinned exactly - see Global Constraints in the plan this was built from.
# Bumping this is a deliberate, separately-tested action.
# This is the commit the v1.0.1 tag points at (2026-11-20). The previous pin
# was pre-1.0 commit 27bf3444 (2026-09-18); see docs/2026-11-v1-rerun.md for
# what changed between the two.
export SUBSTRATE_SHA="20778a6dbb01f13024642851bb592bf67c9fec05"
export SUBSTRATE_DIR="$REPO_ROOT/.vendor/substrate"

export ATESPACE="ate-demo-parking"
# "parking" names both the WorkerPool and the actor template in Substrate's
# own demo manifests (parking.yaml.tmpl / parking-template.yaml.tmpl) - one
# variable serves both call sites below (kubectl ate create --template, and
# WorkerPool lookups) because they are, in fact, the same string.
export WORKERPOOL_NAME="parking"

# The SPIFFE ID `kubectl ate proxy actor` presents to atenet-router. Since
# v1.0 the router only accepts mTLS clients listed in
# --ingress-allowed-spiffe-ids, so setup.sh installs with exactly this ID.
export INGRESS_CLIENT_SPIFFE_ID="spiffe://cluster.local/ns/ate-system/sa/atenet-client"

export DEMO_KUBECONFIG="$REPO_ROOT/.kubeconfig"
# Every script in this repo talks to the demo cluster only - never the
# presenter's default kubeconfig/context.
export KUBECONFIG="$DEMO_KUBECONFIG"

export PATH="$REPO_ROOT/bin:$PATH"
