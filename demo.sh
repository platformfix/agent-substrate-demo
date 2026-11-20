#!/usr/bin/env bash
# The on-stage script. Do not improvise in here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ./env.sh
# shellcheck source=util.sh
source ./util.sh

wait_for_router_stable || {
  echo "atenet-router never stabilized to a single Ready pod" >&2
  exit 1
}
start_actor_proxies p1 p2 p3 p4
trap stop_actor_proxies EXIT

desc "Two workers. Four actors. Let's fill the pool."
run "curl -s http://localhost:$(actor_port p1)"
run "curl -s http://localhost:$(actor_port p2)"
run "kubectl ate get actors -a $ATESPACE"

desc "Now the pool is full. Request a third actor."
pause_for_presenter "[the next request will hang - that's the point]"
desc "In a second terminal, free a worker within the park budget."
( sleep 2; kubectl ate suspend actor p1 -a "$ATESPACE" >/dev/null 2>&1 ) &
run "curl -s -w '\n-> HTTP %{http_code} in %{time_total}s\n' http://localhost:$(actor_port p3)"

desc "That parked. It waited, then resolved. Now watch it fail without parking."
run "kubectl -n ate-system patch deployment atenet-router --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--parked-request-max=0\"}]'"
run "kubectl -n ate-system rollout status deployment/atenet-router --timeout=120s"
wait_for_router_stable
run_expect_fail "curl -sf http://localhost:$(actor_port p4)"

desc "Same saturation. No parking. A real 503."
