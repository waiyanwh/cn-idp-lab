#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

ensure_dirs
require_lab_tools helm

log "Checking shell syntax"
bash -n "${ROOT_DIR}"/scripts/*.sh

if command -v shellcheck >/dev/null 2>&1; then
  log "Running shellcheck"
  shellcheck "${ROOT_DIR}"/scripts/*.sh
else
  log "shellcheck not installed; skipping"
fi

log "Linting Helm charts"
helm lint "${ROOT_DIR}/apps/catalog-api/chart"
helm lint "${ROOT_DIR}/apps/orders-api/chart"

if command -v terraform >/dev/null 2>&1; then
  log "Validating Terraform reference"
  terraform -chdir="${ROOT_DIR}/infra/terraform" fmt -check
  terraform -chdir="${ROOT_DIR}/infra/terraform" init -backend=false
  terraform -chdir="${ROOT_DIR}/infra/terraform" validate
else
  log "terraform not installed; skipping Terraform validation"
fi

"${ROOT_DIR}/scripts/render.sh"

