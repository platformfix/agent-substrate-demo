#!/usr/bin/env bash
# Between rehearsal passes: back to a clean baseline, cluster stays up.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ./env.sh

echo "==> Restoring parking (undoing any --parked-request-max=0 patch)"
kubectl -n ate-system rollout undo deployment/atenet-router 2>/dev/null || true
kubectl -n ate-system rollout status deployment/atenet-router --timeout=60s

echo "==> Suspending all demo actors"
for id in p1 p2 p3 p4; do
  kubectl ate suspend actor "$id" -a "$ATESPACE" 2>/dev/null || true
done

echo "==> Reset complete."
