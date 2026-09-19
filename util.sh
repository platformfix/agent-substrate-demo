#!/usr/bin/env bash
# Shared demo harness. Pattern originated in Christian Posta's
# scripted-solo-demos, adapted via platformfix/k8s-ai-demo.

TYPE_SPEED=25
if [ "${DEMO_RUN_FAST:-0}" = "1" ]; then
  TYPE_SPEED=1000
fi

desc() {
  echo
  echo "# $*"
}

run() {
  local cmd="$*"
  printf '%s' "$cmd" | pv -qL "$TYPE_SPEED"
  echo
  if [ "${DEMO_AUTO_RUN:-0}" != "1" ]; then
    read -rsn1 -p "[press any key to run]"
    echo
  fi
  eval "$cmd"
}

# Flags loudly only if the command unexpectedly succeeds - used for the one
# step that's supposed to fail (proving the 503-without-parking baseline is
# real).
run_expect_fail() {
  local cmd="$*"
  if run "$cmd"; then
    echo "!! Expected '$cmd' to fail, but it succeeded. !!"
    return 1
  fi
  return 0
}

pause_for_presenter() {
  if [ "${DEMO_AUTO_RUN:-0}" != "1" ]; then
    read -rsn1 -p "$1"
    echo
  fi
}

# kubectl port-forward svc/atenet-router binds to one specific backing pod
# for the tunnel's entire lifetime and does NOT reconnect if that pod is
# later deleted (verified directly: force-deleting the bound pod breaks an
# already-open tunnel with "lost connection to pod", the same signature
# preflight.sh hit in back-to-back runs). A prior run's own restore step
# (rollout undo) leaves its outgoing pod alive for --drain-delay (13s)
# after the new one is Ready, so starting the tunnel immediately can bind
# it to a pod that's about to disappear. Wait for exactly one Ready pod -
# no leftover Terminating one - before opening the tunnel at all.
wait_for_router_stable() {
  local i names total ready
  for i in $(seq 1 30); do
    names=$(kubectl -n ate-system get pods -l app=atenet-router -o jsonpath='{.items[*].metadata.name}')
    total=$(wc -w <<<"$names")
    if [ "$total" -eq 1 ]; then
      ready=$(kubectl -n ate-system get pods -l app=atenet-router \
        -o jsonpath='{.items[0].status.containerStatuses[*].ready}')
      if [ -n "$ready" ] && [[ "$ready" != *false* ]]; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

# Belt and suspenders on top of wait_for_router_stable above: if the tunnel
# still ends up bound to a pod that then disappears (e.g. it started
# Terminating in the gap between the stability check and this dial), no
# amount of curl retries against that same dead tunnel will recover it -
# the fix is to tear the port-forward down and re-establish it, not just
# retry the request. Callers must define their own start_port_forward
# (setting PF_PID) before calling this - it re-dials via that function.
restart_port_forward() {
  kill "$PF_PID" 2>/dev/null || true
  wait "$PF_PID" 2>/dev/null || true
  start_port_forward
  sleep 2
}
