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

echo "==> Installing Agent Substrate (kind-local: gVisor, Postgres, hostpath CSI, no cloud)"
# install-ate-kind.sh defaults KIND_CLUSTER_NAME to "kind" and derives
# KUBECTL_CONTEXT="kind-${KIND_CLUSTER_NAME}" from it (see its own source);
# without this it targets the nonexistent "kind-kind" context instead of our
# actual cluster.
#
# It also builds images with `ko`, which resolves base-image references
# (e.g. gcr.io/distroless/...) through the *host's* Docker credential config.
# On a machine where ~/.docker/config.json maps gcr.io to the gcloud
# credential helper (leftover from unrelated GCP work) and that gcloud
# session needs an interactive reauth, ko fails hard trying to authenticate
# what is actually a public, anonymously-pullable image. Point it at an
# empty, isolated Docker config so it never sees that credential helper.
ISOLATED_DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$ISOLATED_DOCKER_CONFIG"' EXIT
echo '{}' > "$ISOLATED_DOCKER_CONFIG/config.json"
KIND_CLUSTER_NAME="$CLUSTER_NAME" DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" \
  ./hack/install-ate-kind.sh --deploy-ate-system

echo "==> Installing the parking demo"
KIND_CLUSTER_NAME="$CLUSTER_NAME" DOCKER_CONFIG="$ISOLATED_DOCKER_CONFIG" \
  ./hack/install-ate-kind.sh --deploy-demo-parking

echo "==> Building and installing kubectl-ate"
mkdir -p "$REPO_ROOT/bin"
GOBIN="$REPO_ROOT/bin" go install ./cmd/kubectl-ate

echo
echo "==> Setup complete. Run ./preflight.sh immediately before you walk on stage."
