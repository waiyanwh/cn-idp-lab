#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

require_lab_tools kubectl

cat <<'EOF'
Demo map:
  1. GitOps drift: kubectl -n apps scale deploy/catalog-api --replicas=0
     Argo CD will restore the declared replica count.
  2. Rollback: edit gitops/app chart values, rerun make deploy, then git revert and make deploy.
  3. Kyverno: demos/kyverno-latest-blocked.yaml must be rejected.
  4. Istio mTLS: apply demos/strict-mtls.yaml, verify app traffic, then restore gitops/apps/networking/peer-authentication.yaml.
  5. Falco: apply demos/falco-trigger.yaml and inspect falco logs.
  6. Seccomp: apply demos/seccomp-runtime-default.yaml and inspect the pod securityContext.
EOF

log "Running safe demo checks"
if lab_kubectl apply --dry-run=server -f "${ROOT_DIR}/demos/kyverno-latest-blocked.yaml" >/dev/null 2>&1; then
  die "Kyverno latest-tag policy did not reject the demo pod"
else
  printf "Kyverno deny demo works\n"
fi

lab_kubectl apply -f "${ROOT_DIR}/demos/seccomp-runtime-default.yaml"
lab_kubectl -n apps wait --for=condition=Ready pod/seccomp-runtime-default --timeout=60s || true
lab_kubectl -n apps get pod seccomp-runtime-default -o jsonpath='{.spec.securityContext.seccompProfile.type}{"\n"}'
lab_kubectl delete -f "${ROOT_DIR}/demos/seccomp-runtime-default.yaml" --ignore-not-found --wait=false >/dev/null

lab_kubectl apply -f "${ROOT_DIR}/demos/falco-trigger.yaml"
sleep 15
lab_kubectl -n falco logs ds/falco --tail=20 || true
lab_kubectl delete -f "${ROOT_DIR}/demos/falco-trigger.yaml" --ignore-not-found --wait=false >/dev/null

log "Demo checks complete"
