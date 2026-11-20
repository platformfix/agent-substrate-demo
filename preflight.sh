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
wait_for_router_stable || fail "atenet-router never stabilized to a single Ready pod"

echo "==> Starting kubectl ate proxies (p1-p4 on localhost:8001-8004)"
start_actor_proxies p1 p2 p3 p4 || fail "an actor proxy did not start"
trap stop_actor_proxies EXIT

echo "==> Filling both workers (p1, p2 -> RUNNING)"
# A first resume can be refused while the actor is still coming up (v1.0.1
# answers "503 actor <ref> is still resuming, retry"), which the proxy turns
# into a closed connection, so retry a few times before giving up.
resume_via_curl() {
  local id="$1"
  for _ in $(seq 1 15); do
    curl -sf "http://localhost:$(actor_port "$id")" >/dev/null && return 0
    sleep 2
  done
  echo "--- proxy log for $id ---" >&2
  cat "$(actor_proxy_log "$id")" >&2
  return 1
}
resume_via_curl p1 || fail "p1 did not resume"
resume_via_curl p2 || fail "p2 did not resume"

echo "==> Proving a parked request resolves (p3, while p1 suspends within budget)"
( sleep 1; kubectl ate suspend actor p1 -a "$ATESPACE" >/dev/null 2>&1 ) &
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$(actor_port p3)" || true)
[ "$code" = "200" ] || fail "expected p3 to park then succeed (200), got $code"
echo "    PASS: parked request resolved with 200"

echo "==> Proving a request fails fast with parking disabled (p4)"
kubectl -n ate-system patch deployment atenet-router --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--parked-request-max=0"}]'
kubectl -n ate-system rollout status deployment/atenet-router --timeout=120s
wait_for_router_stable || fail "atenet-router never stabilized after disabling parking"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$(actor_port p4)" || true)
[ "$code" = "503" ] || fail "expected p4 to fail fast (503) with parking off, got $code"
echo "    PASS: request failed fast with 503 (parking off)"

echo "==> Restoring the baseline (parking on, actors suspended)"
kubectl -n ate-system rollout undo deployment/atenet-router
kubectl -n ate-system rollout status deployment/atenet-router --timeout=120s
for id in p1 p2 p3 p4; do
  kubectl ate suspend actor "$id" -a "$ATESPACE" 2>/dev/null || true
done

echo
echo "==> PREFLIGHT PASSED. Cluster is in the baseline state demo.sh expects."
