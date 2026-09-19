#!/usr/bin/env bash
# Immediately before you walk on stage. Proves both outcomes for real, then
# restores the baseline demo.sh expects.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ./env.sh
# shellcheck source=util.sh
source ./util.sh

fail() {
  echo "PREFLIGHT FAILED: $1" >&2
  exit 1
}

echo "==> Creating four actors (p1-p4) sharing the 2-worker pool"
for id in p1 p2 p3 p4; do
  kubectl ate create actor "$id" -a "$ATESPACE" --template "$WORKERPOOL_NAME" \
    2>/dev/null || true # idempotent - already exists is fine
done

echo "==> Port-forwarding atenet-router to localhost:8000"
kubectl port-forward -n ate-system svc/atenet-router 8000:80 \
  >/tmp/preflight-portforward.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 2

echo "==> Filling both workers (p1, p2 -> RUNNING)"
# Retries: a router that just came back from a prior run's own patch/undo
# cycle can still be mid-drain (its --drain-delay on the outgoing pod) when
# this port-forward resolves its backing pod, producing a transient
# "connection refused" that isn't actually about the actor's resume path.
resume_via_curl() {
  local id="$1" attempt
  for attempt in $(seq 1 15); do
    curl -sf -H "ate-target-actor: $ATESPACE/$id" http://localhost:8000 >/dev/null && return 0
    sleep 1
  done
  return 1
}
resume_via_curl p1 || fail "p1 did not resume"
resume_via_curl p2 || fail "p2 did not resume"

echo "==> Proving a parked request resolves (p3, while p1 suspends within budget)"
( sleep 1; kubectl ate suspend actor p1 -a "$ATESPACE" ) &
code=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "ate-target-actor: $ATESPACE/p3" http://localhost:8000)
[ "$code" = "200" ] || fail "expected p3 to park then succeed (200), got $code"
echo "    PASS: parked request resolved with 200"

echo "==> Proving a request fails fast with parking disabled (p4)"
kubectl -n ate-system patch deployment atenet-router --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--parked-request-max=0"}]'
kubectl -n ate-system rollout status deployment/atenet-router --timeout=60s
code=$(curl -s -o /dev/null -w '%{http_code}' \
  -H "ate-target-actor: $ATESPACE/p4" http://localhost:8000)
[ "$code" = "503" ] || fail "expected p4 to fail fast (503) with parking off, got $code"
echo "    PASS: request failed fast with 503 (parking off)"

echo "==> Restoring the baseline (parking on, actors suspended)"
kubectl -n ate-system rollout undo deployment/atenet-router
kubectl -n ate-system rollout status deployment/atenet-router --timeout=60s
for id in p1 p2 p3 p4; do
  kubectl ate suspend actor "$id" -a "$ATESPACE" 2>/dev/null || true
done

echo
echo "==> PREFLIGHT PASSED. Cluster is in the baseline state demo.sh expects."
