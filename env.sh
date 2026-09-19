#!/usr/bin/env bash
# Single place to change identifiers - never touched by demo.sh itself.
# Pattern: platformfix/k8s-ai-demo's env.sh.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT

export CLUSTER_NAME="agent-substrate-demo"
export KIND_REGISTRY_PORT="5001"

# Pinned exactly - see Global Constraints in the plan this was built from.
# Bumping this is a deliberate, separately-tested action.
export SUBSTRATE_SHA="27bf34444e0c1a8762aebcafbc733a97c023cb4d"
export SUBSTRATE_DIR="$REPO_ROOT/.vendor/substrate"

export ATESPACE="ate-demo-parking"
# "parking" names both the WorkerPool and the actor template in Substrate's
# own demo manifests (parking.yaml.tmpl / parking-template.yaml.tmpl) - one
# variable serves both call sites below (kubectl ate create --template, and
# WorkerPool lookups) because they are, in fact, the same string.
export WORKERPOOL_NAME="parking"

export DEMO_KUBECONFIG="$REPO_ROOT/.kubeconfig"
# Every script in this repo talks to the demo cluster only - never the
# presenter's default kubeconfig/context.
export KUBECONFIG="$DEMO_KUBECONFIG"

export PATH="$REPO_ROOT/bin:$PATH"
