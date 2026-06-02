#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

check_docker
if command -v kind >/dev/null 2>&1 && kind get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  log "Deleting kind cluster ${KIND_CLUSTER_NAME}"
  kind delete cluster --name "${KIND_CLUSTER_NAME}"
elif [[ -x "${BIN_DIR}/kind" ]] && "${BIN_DIR}/kind" get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  log "Deleting kind cluster ${KIND_CLUSTER_NAME}"
  "${BIN_DIR}/kind" delete cluster --name "${KIND_CLUSTER_NAME}"
fi

if docker inspect "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1; then
  log "Removing local registry ${LOCAL_REGISTRY_NAME}"
  docker rm -f "${LOCAL_REGISTRY_NAME}" >/dev/null
fi

log "Removing generated lab state"
rm -rf "${LAB_DIR}" "${DIST_DIR}" "${REPORTS_DIR}"

log "Cleanup complete"
