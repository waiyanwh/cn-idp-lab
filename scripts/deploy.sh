#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

ensure_dirs
need_cmd git
need_cmd curl
require_lab_tools kubectl

if [[ ! -f "${COSIGN_DIR}/cosign.pub" ]]; then
  log "Cosign public key is missing; running the supply-chain pipeline first"
  "${ROOT_DIR}/scripts/pipeline.sh"
fi

render_cosign_policy() {
  local template="${ROOT_DIR}/gitops/platform/kyverno-policies/verify-signed-image.yaml.tpl"
  local output="${GITOPS_WORKDIR}/platform/kyverno-policies/verify-signed-image.yaml"
  awk -v keyfile="${COSIGN_DIR}/cosign.pub" '
    /__COSIGN_PUBLIC_KEY__/ {
      while ((getline line < keyfile) > 0) {
        print "                      " line
      }
      close(keyfile)
      next
    }
    { print }
  ' "${template}" >"${output}"
  rm -f "${GITOPS_WORKDIR}/platform/kyverno-policies/verify-signed-image.yaml.tpl"
}

start_gitea_port_forward() {
  local port="$1"
  local log_file="${LAB_DIR}/gitea-port-forward.log"
  lab_kubectl -n gitea port-forward svc/gitea-http "${port}:3000" >"${log_file}" 2>&1 &
  GITEA_PF_PID=$!
  sleep 2
  wait_for_http "http://127.0.0.1:${port}/api/healthz" 120
}

create_gitea_repo() {
  local port="$1"
  local payload
  payload="$(printf '{"name":"%s","private":false,"auto_init":false}' "${GITEA_REPO}")"
  curl -fsS -u "${GITEA_USERNAME}:${GITEA_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "${payload}" \
    "http://127.0.0.1:${port}/api/v1/user/repos" >/dev/null || true
}

prepare_gitops_repo() {
  rm -rf "${GITOPS_WORKDIR}"
  mkdir -p "${GITOPS_WORKDIR}/apps/catalog-api" "${GITOPS_WORKDIR}/apps/orders-api"
  cp -R "${ROOT_DIR}/gitops/." "${GITOPS_WORKDIR}/"
  cp -R "${ROOT_DIR}/apps/catalog-api/chart" "${GITOPS_WORKDIR}/apps/catalog-api/chart"
  cp -R "${ROOT_DIR}/apps/orders-api/chart" "${GITOPS_WORKDIR}/apps/orders-api/chart"
  render_cosign_policy
}

push_gitops_repo() {
  local port="$1"
  local remote="http://${GITEA_USERNAME}:${GITEA_PASSWORD}@127.0.0.1:${port}/${GITEA_USERNAME}/${GITEA_REPO}.git"
  (
    cd "${GITOPS_WORKDIR}"
    git init -b main >/dev/null
    git config user.name "CNCF IDP Lab"
    git config user.email "platform@example.com"
    git add .
    git commit -m "sync local idp gitops content" >/dev/null
    git remote add origin "${remote}"
    git push -f origin main
  )
}

configure_vault() {
  log "Configuring Vault Kubernetes auth and sample secrets"
  wait_for_statefulset vault vault 300s
  lab_kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s
  lab_kubectl -n vault exec -i vault-0 -- sh -s <<'VAULT_SCRIPT'
set -e
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root

vault secrets enable -path=secret kv-v2 >/dev/null 2>&1 || true
vault auth enable kubernetes >/dev/null 2>&1 || true

vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt >/dev/null

vault policy write catalog-api - >/dev/null <<'POLICY'
path "secret/data/catalog-api" {
  capabilities = ["read"]
}
POLICY

vault policy write orders-api - >/dev/null <<'POLICY'
path "secret/data/orders-api" {
  capabilities = ["read"]
}
POLICY

vault write auth/kubernetes/role/catalog-api \
  bound_service_account_names=catalog-api \
  bound_service_account_namespaces=apps \
  policies=catalog-api \
  ttl=24h >/dev/null

vault write auth/kubernetes/role/orders-api \
  bound_service_account_names=orders-api \
  bound_service_account_namespaces=apps \
  policies=orders-api \
  ttl=24h >/dev/null

vault kv put secret/catalog-api message="catalog secret from Vault CSI" >/dev/null
vault kv put secret/orders-api message="orders secret from Vault CSI" >/dev/null
VAULT_SCRIPT
}

log "Preparing in-cluster Gitea repository"
lab_kubectl -n gitea exec deploy/gitea -- su git -c \
  "gitea admin user create --config /data/gitea/conf/app.ini --username ${GITEA_USERNAME} --password ${GITEA_PASSWORD} --email platform@example.com --admin --must-change-password=false" >/dev/null 2>&1 || true

GITEA_LOCAL_PORT="${GITEA_LOCAL_PORT:-13000}"
start_gitea_port_forward "${GITEA_LOCAL_PORT}"
trap 'kill "${GITEA_PF_PID}" >/dev/null 2>&1 || true' EXIT

create_gitea_repo "${GITEA_LOCAL_PORT}"
prepare_gitops_repo
push_gitops_repo "${GITEA_LOCAL_PORT}"

log "Applying Argo CD root application"
lab_kubectl apply -f "${ROOT_DIR}/platform/bootstrap/root-application.yaml"
lab_kubectl -n argocd annotate application idp-root argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
lab_kubectl -n argocd annotate application idp-platform argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
lab_kubectl -n argocd annotate application idp-apps argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true

log "Waiting for Argo CD application tree"
wait_for_argocd_app idp-root 600
wait_for_argocd_app idp-platform 900
wait_for_argocd_app kyverno 900
wait_for_argocd_app secrets-store-csi-driver 900
wait_for_argocd_app vault 900
wait_for_argocd_app vault-config 600
configure_vault
wait_for_argocd_app istio-base 900
wait_for_argocd_app istiod 900
wait_for_argocd_app istio-ingressgateway 900
wait_for_argocd_app kube-prometheus-stack 900
wait_for_argocd_app loki 900
wait_for_argocd_app promtail 900
wait_for_argocd_app falco 900
wait_for_argocd_app kyverno-policies 900
wait_for_argocd_app idp-apps 900
wait_for_argocd_app app-namespaces 600
wait_for_argocd_app catalog-api 900
wait_for_argocd_app orders-api 900

wait_for_deployment apps catalog-api 300s
wait_for_deployment apps orders-api 300s

log "Deployment complete"
printf "Catalog API: http://localhost:8080/catalog\n"
printf "Orders API:  http://localhost:8080/orders\n"
