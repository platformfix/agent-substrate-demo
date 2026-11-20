#!/usr/bin/env bash
# Run once, in the green room. Idempotent - safe to re-run.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=env.sh
source ./env.sh

echo "==> Checking required tools"
for bin in git go kind kubectl docker pv; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "Missing required tool: $bin"
    exit 1
  }
done

echo "==> Vendoring agent-substrate/substrate @ $SUBSTRATE_SHA"
if [ -d "$SUBSTRATE_DIR/.git" ]; then
  echo "    already vendored, skipping clone"
  # A checkout left over from before a pin bump would otherwise install the
  # old Substrate silently.
  vendored_sha="$(git -C "$SUBSTRATE_DIR" rev-parse HEAD)"
  if [ "$vendored_sha" != "$SUBSTRATE_SHA" ]; then
    echo "Vendored Substrate is at $vendored_sha, not the pinned $SUBSTRATE_SHA."
    echo "Remove it and re-run: rm -rf .vendor/substrate"
    exit 1
  fi
else
  mkdir -p "$(dirname "$SUBSTRATE_DIR")"
  git clone --quiet https://github.com/agent-substrate/substrate.git "$SUBSTRATE_DIR"
  git -C "$SUBSTRATE_DIR" checkout --quiet "$SUBSTRATE_SHA"
fi

cd "$SUBSTRATE_DIR"

echo "==> Creating kind cluster ($CLUSTER_NAME)"
KIND_CLUSTER_NAME="$CLUSTER_NAME" KIND_REGISTRY_PORT="$KIND_REGISTRY_PORT" \
  ./hack/create-kind-cluster.sh
kind get kubeconfig --name "$CLUSTER_NAME" > "$DEMO_KUBECONFIG"

echo "==> Installing Agent Substrate (kind-local: gVisor, Postgres, rustfs, no cloud)"
# Substrate v1.0 deleted hack/install-ate-kind.sh (upstream PR #3354); the
# installer is now the Go command cmd/ate-setup. ATE_INSTALL_KIND selects the
# kind overlays, the local registry and host-architecture builds, and
# KUBECTL_CONTEXT points it at our cluster rather than the default "kind-kind".
#
# --ingress-allowed-spiffe-ids is new and not optional in practice: unset, the
# router lets no client reach any actor. INGRESS_CLIENT_SPIFFE_ID (env.sh) is
# the identity `kubectl ate proxy actor` presents.
#
# Images are still built with `ko` (now run via `go run`, so no ko binary is
# needed), which resolves base-image references through the *host's* Docker
# credential config. On a machine where ~/.docker/config.json maps gcr.io to
# the gcloud credential helper and that gcloud session needs an interactive
# reauth, ko fails hard trying to authenticate a public, anonymously-pullable
# image. Point it at an empty, isolated Docker config so it never sees that.
ISOLATED_DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$ISOLATED_DOCKER_CONFIG"' EXIT
echo '{}' > "$ISOLATED_DOCKER_CONFIG/config.json"
# Since v1.0 the install also builds the envoy-dataplane image with
# `docker buildx`. Docker looks for CLI plugins under $DOCKER_CONFIG, so the
# isolated config hides a per-user buildx install and the build fails with
# "unknown flag: --platform". Carry the plugins (never the credentials) over.
if [ -d "$HOME/.docker/cli-plugins" ]; then
  ln -s "$HOME/.docker/cli-plugins" "$ISOLATED_DOCKER_CONFIG/cli-plugins"
fi
export ATE_INSTALL_KIND=true
export KUBECTL_CONTEXT="kind-$CLUSTER_NAME"
export KIND_CLUSTER_NAME="$CLUSTER_NAME"
export KO_DOCKER_REPO="${KO_DOCKER_REPO:-localhost:$KIND_REGISTRY_PORT}"
DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" go run ./cmd/ate-setup deploy ate-system \
  --sandbox-classes=gvisor \
  --credential-provider='{"name":"k8s.io"}' \
  --ingress-allowed-spiffe-ids="$INGRESS_CLIENT_SPIFFE_ID"

echo "==> Installing the parking demo"
DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" go run ./cmd/ate-setup deploy demo parking

echo "==> Building and installing kubectl-ate"
mkdir -p "$REPO_ROOT/bin"
GOBIN="$REPO_ROOT/bin" go install ./cmd/kubectl-ate

echo
echo "==> Setup complete. Run ./preflight.sh immediately before you walk on stage."
