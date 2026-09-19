#!/usr/bin/env bash
# After the conference: delete the kind cluster and its registry.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ./env.sh
cd "$SUBSTRATE_DIR"
KIND_CLUSTER_NAME="$CLUSTER_NAME" ./hack/delete-kind-cluster.sh
