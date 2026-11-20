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

# Since Substrate v1.0, atenet-router has no plain-HTTP port: its Service
# exposes only 443 (HTTPS) and 8444 (TLS CONNECT), and every client must
# present a Pod Identity certificate whose SPIFFE ID is on the install's
# --ingress-allowed-spiffe-ids list. The old approach (kubectl port-forward
# svc/atenet-router 8000:80 plus an ate-target-actor header on a plain curl)
# therefore no longer has anything to connect to. `kubectl ate proxy actor`
# is the supported client: it gets that certificate, opens a fresh
# port-forward and CONNECT tunnel through the router per TCP connection, and
# serves plain HTTP on a local port.
#
# Saturation still surfaces as a real HTTP 503 at curl: the router accepts
# the CONNECT tunnel and Envoy answers the request inside it with
# "503 ... no worker has room for the actor". Each proxy logs to its own file
# so a refused tunnel (a different failure) is still diagnosable.
#
# Actor pN (or any name ending in digit N) is served on local port 800N.
actor_port() {
  echo "800${1//[!0-9]/}"
}

actor_proxy_log() {
  echo "${PROXY_LOG_DIR:?}/$1.proxy.log"
}

start_actor_proxies() {
  local id log found
  PROXY_LOG_DIR="$(mktemp -d)"
  PROXY_PIDS=()
  for id in "$@"; do
    log="$(actor_proxy_log "$id")"
    kubectl ate proxy actor "$id" "$(actor_port "$id"):80" -a "$ATESPACE" >"$log" 2>&1 &
    PROXY_PIDS+=($!)
  done
  for id in "$@"; do
    log="$(actor_proxy_log "$id")"
    found=0
    for _ in $(seq 1 100); do
      if grep -q "^Proxying " "$log" 2>/dev/null; then
        found=1
        break
      fi
      sleep 0.2
    done
    if [ "$found" -ne 1 ]; then
      echo "proxy for $id never became ready:" >&2
      cat "$log" >&2
      return 1
    fi
  done
}

stop_actor_proxies() {
  if [ "${#PROXY_PIDS[@]}" -gt 0 ]; then
    kill "${PROXY_PIDS[@]}" 2>/dev/null || true
  fi
}

# The demo rolls atenet-router (to turn parking off and back on), and the
# outgoing pod lingers for --drain-delay (13s) after the new one is Ready.
# kubectl ate proxy picks a ready pod per connection, so this matters less
# than it did with one long-lived port-forward, but waiting for exactly one
# Ready pod keeps every beat starting from the same state.
wait_for_router_stable() {
  local names total ready
  for _ in $(seq 1 60); do
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
