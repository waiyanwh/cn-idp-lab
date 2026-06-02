#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

ensure_dirs
check_docker
require_lab_tools kind kubectl helm

log "Starting local registry ${LOCAL_REGISTRY_NAME}"
docker network inspect kind >/dev/null 2>&1 || docker network create kind >/dev/null
if ! docker inspect "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1; then
  docker run -d --restart=always -p "127.0.0.1:${LOCAL_REGISTRY_PORT}:5000" --name "${LOCAL_REGISTRY_NAME}" registry:2 >/dev/null
elif [[ "$(docker inspect -f '{{.State.Running}}' "${LOCAL_REGISTRY_NAME}")" != "true" ]]; then
  docker start "${LOCAL_REGISTRY_NAME}" >/dev/null
fi
docker network connect kind "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1 || true

log "Creating or reusing kind cluster ${KIND_CLUSTER_NAME}"
if ! kind get clusters | grep -qx "${KIND_CLUSTER_NAME}"; then
  kind create cluster --name "${KIND_CLUSTER_NAME}" --image "${KIND_NODE_IMAGE}" --config "${ROOT_DIR}/infra/kind/cluster.yaml"
fi
docker network connect kind "${LOCAL_REGISTRY_NAME}" >/dev/null 2>&1 || true

registry_ip="$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' "${LOCAL_REGISTRY_NAME}")"
[[ -n "${registry_ip}" ]] || die "could not determine ${LOCAL_REGISTRY_NAME} IP on the kind network"

lab_kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${LOCAL_REGISTRY_PORT}"
    clusterHost: "${CLUSTER_REGISTRY_HOST}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
---
apiVersion: v1
kind: Service
metadata:
  name: registry
  namespace: kube-system
spec:
  ports:
    - name: registry
      port: ${LOCAL_REGISTRY_PORT}
      protocol: TCP
      targetPort: 5000
---
apiVersion: v1
kind: Endpoints
metadata:
  name: registry
  namespace: kube-system
subsets:
  - addresses:
      - ip: ${registry_ip}
    ports:
      - name: registry
        port: 5000
        protocol: TCP
EOF

log "Installing Calico ${CALICO_VERSION}"
lab_kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
wait_for_daemonset kube-system calico-node 300s
wait_for_deployment kube-system calico-kube-controllers 300s
lab_kubectl -n kube-system rollout status deployment/coredns --timeout=180s

log "Installing bootstrap Gitea"
lab_kubectl apply -f "${ROOT_DIR}/platform/bootstrap/gitea.yaml"
wait_for_deployment gitea gitea 300s

log "Ensuring Gitea admin user"
lab_kubectl -n gitea exec deploy/gitea -- su git -c \
  "gitea admin user create --config /data/gitea/conf/app.ini --username ${GITEA_USERNAME} --password ${GITEA_PASSWORD} --email platform@example.com --admin --must-change-password=false" >/dev/null 2>&1 || true

log "Installing Argo CD ${ARGOCD_CHART_VERSION}"
lab_helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
lab_helm repo update >/dev/null
lab_helm upgrade --install argocd argo/argo-cd \
  --version "${ARGOCD_CHART_VERSION}" \
  --namespace argocd \
  --create-namespace \
  --values "${ROOT_DIR}/platform/bootstrap/argocd-values.yaml"

wait_for_deployment argocd argocd-server 300s
wait_for_deployment argocd argocd-repo-server 300s
wait_for_deployment argocd argocd-applicationset-controller 300s
wait_for_statefulset argocd argocd-application-controller 300s

log "Bootstrap complete"
printf "Gitea service: http://gitea-http.gitea.svc.cluster.local:3000\n"
printf "Argo CD UI: kubectl --context %s -n argocd port-forward svc/argocd-server 8081:80\n" "${KIND_CONTEXT}"
