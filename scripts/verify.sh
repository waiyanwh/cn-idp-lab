#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

require_lab_tools kubectl

log "Checking core workloads"
wait_for_deployment gitea gitea 120s
wait_for_deployment argocd argocd-server 120s
wait_for_deployment apps catalog-api 180s
wait_for_deployment apps orders-api 180s
wait_for_statefulset vault vault 180s

log "Checking Argo CD applications"
lab_kubectl -n argocd get applications

log "Checking HTTP gateway"
curl -fsS http://localhost:8080/catalog | tee "${REPORTS_DIR}/catalog-response.json" >/dev/null
curl -fsS http://localhost:8080/orders | tee "${REPORTS_DIR}/orders-response.json" >/dev/null

log "Checking Kyverno latest-tag denial"
if lab_kubectl apply --dry-run=server -f "${ROOT_DIR}/demos/kyverno-latest-blocked.yaml" >/dev/null 2>&1; then
  die "expected Kyverno to reject nginx:latest, but dry-run succeeded"
else
  printf "Kyverno rejected nginx:latest as expected\n"
fi

log "Checking NetworkPolicy denial from blocked namespace"
lab_kubectl apply -f "${ROOT_DIR}/demos/network-denied.yaml" >/dev/null
if ! lab_kubectl -n blocked-client wait --for=jsonpath='{.status.phase}'=Succeeded pod/blocked-client --timeout=60s >/dev/null 2>&1; then
  lab_kubectl -n blocked-client get pod blocked-client -o wide || true
  lab_kubectl -n blocked-client logs pod/blocked-client --request-timeout=10s || true
  lab_kubectl delete -f "${ROOT_DIR}/demos/network-denied.yaml" --ignore-not-found --wait=false >/dev/null
  die "expected blocked-client to be denied by NetworkPolicy"
fi
lab_kubectl -n blocked-client logs pod/blocked-client --request-timeout=10s || true
lab_kubectl delete -f "${ROOT_DIR}/demos/network-denied.yaml" --ignore-not-found --wait=false >/dev/null

log "Checking Cosign verification reports"
test -s "${REPORTS_DIR}/cosign-catalog-api.json"
test -s "${REPORTS_DIR}/cosign-orders-api.json"
test -s "${REPORTS_DIR}/cosign-cluster-verify-catalog-api.txt"
test -s "${REPORTS_DIR}/cosign-cluster-verify-orders-api.txt"

log "Verification complete"
