#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

ensure_dirs
require_lab_tools helm

mkdir -p "${DIST_DIR}/rendered"
helm template catalog-api "${ROOT_DIR}/apps/catalog-api/chart" --namespace apps >"${DIST_DIR}/rendered/catalog-api.yaml"
helm template orders-api "${ROOT_DIR}/apps/orders-api/chart" --namespace apps >"${DIST_DIR}/rendered/orders-api.yaml"
cat "${DIST_DIR}/rendered/catalog-api.yaml" "${DIST_DIR}/rendered/orders-api.yaml" >"${DIST_DIR}/rendered/apps.yaml"
log "Rendered app manifests into ${DIST_DIR}/rendered"

