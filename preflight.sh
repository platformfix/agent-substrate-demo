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

echo "==> Waiting for atenet-router to be a single stable pod"
# wait_for_router_stable lives in util.sh (shared with demo.sh).
wait_for_router_stable || fail "atenet-router never stabilized to a single Ready pod"

echo "==> Port-forwarding atenet-router to localhost:8000"
start_port_forward() {
  kubectl port-forward -n ate-system svc/atenet-router 8000:80 \
    >/tmp/preflight-portforward.log 2>&1 &
  PF_PID=$!
}
# restart_port_forward lives in util.sh (shared with demo.sh); it calls
# start_port_forward above and expects PF_PID, both defined here.
start_port_forward
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 2

echo "==> Filling both workers (p1, p2 -> RUNNING)"
# Belt and suspenders on top of wait_for_router_stable above: if the tunnel
# still ends up bound to a pod that then disappears (e.g. it started
# Terminating in the gap between the stability check and this dial), no
# amount of curl retries against that same dead tunnel will recover it -
# the fix is to tear the port-forward down and re-establish it, not just
# retry the request. A curl -f exit code of 22 means the server actually
# answered with a bad HTTP status - a real backend problem, not a broken
# tunnel - so that one is NOT retried.
resume_via_curl() {
  local id="$1" attempt rc
  for attempt in $(seq 1 15); do
    curl -sf -H "ate-target-actor: $ATESPACE/$id" http://localhost:8000 >/dev/null && return 0
    rc=$?
    if [ "$rc" -eq 22 ]; then
      return 1
    fi
    restart_port_forward # from util.sh
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
