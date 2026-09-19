#!/usr/bin/env bash
# The on-stage script. Do not improvise in here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ./env.sh
# shellcheck source=util.sh
source ./util.sh

start_port_forward() {
  kubectl port-forward -n ate-system svc/atenet-router 8000:80 \
    >/tmp/demo-portforward.log 2>&1 &
  PF_PID=$!
}

wait_for_router_stable || {
  echo "atenet-router never stabilized to a single Ready pod" >&2
  exit 1
}
start_port_forward
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 2

desc "Two workers. Four actors. Let's fill the pool."
run "curl -s -H 'ate-target-actor: $ATESPACE/p1' http://localhost:8000"
run "curl -s -H 'ate-target-actor: $ATESPACE/p2' http://localhost:8000"
run "kubectl ate get actors -a $ATESPACE"

desc "Now the pool is full. Request a third actor."
pause_for_presenter "[the next request will hang - that's the point]"
desc "In a second terminal, free a worker within the park budget."
( sleep 2; kubectl ate suspend actor p1 -a "$ATESPACE" ) &
run "curl -s -w '\n-> HTTP %{http_code} in %{time_total}s\n' -H 'ate-target-actor: $ATESPACE/p3' http://localhost:8000"

desc "That parked. It waited, then resolved. Now watch it fail without parking."
run "kubectl -n ate-system patch deployment atenet-router --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--parked-request-max=0\"}]'"
run "kubectl -n ate-system rollout status deployment/atenet-router --timeout=60s"
run_expect_fail "curl -sf -H 'ate-target-actor: $ATESPACE/p4' http://localhost:8000"

desc "Same saturation. No parking. A real 503."
