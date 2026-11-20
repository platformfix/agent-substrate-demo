#!/usr/bin/env bash
# Probe: does one gVisor actor going over its memory limit take down its
# neighbour on the same worker? (Substrate v1.0 release note, PR #3106.)
#
# Run after ../../setup.sh, against the same kind cluster. Prints what it
# observes; it asserts nothing, because the point is to record what happened.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ../../env.sh
# shellcheck source=util.sh
source ../../util.sh

PROBE_NS="ate-probe-memlimit"
export ATESPACE="$PROBE_NS" # util.sh's proxy helpers read ATESPACE

echo "==> Building memhog and pushing it to the kind registry"
GOOS=linux GOARCH="$(go env GOARCH)" CGO_ENABLED=0 go build -o memhog .
docker build -q -t "localhost:$KIND_REGISTRY_PORT/memhog:probe" . >/dev/null
docker push -q "localhost:$KIND_REGISTRY_PORT/memhog:probe" >/dev/null
digest="$(docker inspect --format '{{index .RepoDigests 0}}' "localhost:$KIND_REGISTRY_PORT/memhog:probe")"
export MEMHOG_IMAGE="$digest"
echo "    $MEMHOG_IMAGE"

echo "==> Creating a one-worker pool with the parking demo's worker image"
WORKER_IMAGE="$(kubectl -n ate-demo-parking get workerpool parking -o jsonpath='{.spec.workerImage}')"
export WORKER_IMAGE
envsubst <pool.yaml.tmpl | kubectl apply -f -
kubectl -n "$PROBE_NS" rollout status deployment/memlimit --timeout=180s 2>/dev/null ||
  kubectl -n "$PROBE_NS" wait --for=condition=Ready pod -l workload=memlimit --timeout=180s || true
kubectl -n "$PROBE_NS" get pods -o wide

echo "==> Creating the atespace, the memhog template, and two actors (m1, m2)"
kubectl ate create atespace "$PROBE_NS" 2>/dev/null || true
envsubst <template.yaml.tmpl | kubectl ate create actor-template -f - 2>/dev/null || true
for _ in $(seq 1 90); do
  golden="$(kubectl ate get actor-templates -a "$PROBE_NS" | awk 'NR==2{print $4}')"
  [ -n "$golden" ] && [ "$golden" != "ERROR" ] && break
  sleep 2
done
kubectl ate get actor-templates -a "$PROBE_NS"
for id in m1 m2; do
  kubectl ate create actor "$id" -a "$PROBE_NS" --template memhog 2>/dev/null || true
done

start_actor_proxies m1 m2
trap stop_actor_proxies EXIT

echo "==> Waking both actors; they should share the single worker"
curl -s --retry 10 --retry-all-errors --retry-delay 2 "http://localhost:$(actor_port m1)"
curl -s --retry 10 --retry-all-errors --retry-delay 2 "http://localhost:$(actor_port m2)"
kubectl ate get actors -a "$PROBE_NS"
echo "--- worker pod before (note RESTARTS) ---"
kubectl -n "$PROBE_NS" get pods

echo "==> m1: allocate 400MiB against a 256Mi limit"
start=$(date +%s)
curl -s -m 60 -w '\n-> m1 HTTP %{http_code} in %{time_total}s\n' \
  "http://localhost:$(actor_port m1)/alloc?mib=400" || echo "-> m1 curl exit $?"

echo "==> m2 (the neighbour), once a second for 10s"
for _ in $(seq 1 10); do
  printf '[+%ss] ' "$(($(date +%s) - start))"
  curl -s -m 5 -w ' (HTTP %{http_code})\n' "http://localhost:$(actor_port m2)" || echo "curl exit $?"
  sleep 1
done

echo "==> State after"
kubectl ate get actors -a "$PROBE_NS"
kubectl ate get actor m1 -a "$PROBE_NS" -o yaml 2>/dev/null | grep -iE -A3 'crash|state|message' || true
echo "--- worker pod after (note RESTARTS) ---"
kubectl -n "$PROBE_NS" get pods
echo "--- m1 proxy log ---"
cat "$(actor_proxy_log m1)"
