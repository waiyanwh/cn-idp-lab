#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

ensure_dirs
check_docker
need_cmd python3
require_lab_tools cosign trivy kubesec helm kubectl

export DOCKER_CONFIG="${LAB_DIR}/docker-config"
export TRIVY_CACHE_DIR="${LAB_DIR}/trivy-cache"
mkdir -p "${DOCKER_CONFIG}" "${TRIVY_CACHE_DIR}"
if [[ ! -f "${DOCKER_CONFIG}/config.json" ]]; then
  printf '{}\n' >"${DOCKER_CONFIG}/config.json"
fi

registry_url="http://127.0.0.1:${LOCAL_REGISTRY_PORT}/v2/"
wait_for_http "${registry_url}" 60
lab_kubectl get namespace kube-system >/dev/null

publish_cosign_secret() {
  lab_kubectl -n kube-system create secret generic idp-cosign-key \
    --from-file=cosign.key="${COSIGN_DIR}/cosign.key" \
    --from-file=cosign.pub="${COSIGN_DIR}/cosign.pub" \
    --dry-run=client \
    -o yaml | lab_kubectl apply -f - >/dev/null
}

run_cluster_cosign() {
  local action="$1"
  local app="$2"
  local ref job
  ref="$(cluster_image_ref "${app}")"
  job="cosign-${action}-${app}"
  lab_kubectl -n kube-system delete job "${job}" --ignore-not-found --wait=true >/dev/null
  if [[ "${action}" == "sign" ]]; then
    lab_kubectl -n kube-system apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: cosign
          image: ghcr.io/sigstore/cosign/cosign:${COSIGN_VERSION}
          args:
            - sign
            - --key
            - /keys/cosign.key
            - --allow-insecure-registry
            - --yes
            - ${ref}
          env:
            - name: COSIGN_PASSWORD
              value: ${COSIGN_PASSWORD:-lab-password}
          volumeMounts:
            - name: cosign-key
              mountPath: /keys
              readOnly: true
      volumes:
        - name: cosign-key
          secret:
            secretName: idp-cosign-key
EOF
  else
    lab_kubectl -n kube-system apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: cosign
          image: ghcr.io/sigstore/cosign/cosign:${COSIGN_VERSION}
          args:
            - verify
            - --key
            - /keys/cosign.pub
            - --allow-insecure-registry
            - ${ref}
          volumeMounts:
            - name: cosign-key
              mountPath: /keys
              readOnly: true
      volumes:
        - name: cosign-key
          secret:
            secretName: idp-cosign-key
EOF
  fi
  if ! lab_kubectl -n kube-system wait --for=condition=Complete "job/${job}" --timeout=180s; then
    lab_kubectl -n kube-system logs "job/${job}" || true
    die "cluster cosign ${action} failed for ${ref}"
  fi
  lab_kubectl -n kube-system logs "job/${job}" >"${REPORTS_DIR}/cosign-cluster-${action}-${app}.txt"
}

log "Running unit tests"
PYTHONPATH="${ROOT_DIR}/apps/catalog-api" python3 -m unittest discover -s "${ROOT_DIR}/apps/catalog-api/tests"
PYTHONPATH="${ROOT_DIR}/apps/orders-api" python3 -m unittest discover -s "${ROOT_DIR}/apps/orders-api/tests"

if command -v bandit >/dev/null 2>&1; then
  log "Running Bandit SAST"
  bandit -q -r "${ROOT_DIR}/apps" -x "*/tests/*" -f json -o "${REPORTS_DIR}/bandit.json" || true
else
  log "Bandit not installed; run make tools to enable SAST"
fi

log "Running Trivy filesystem scan"
trivy fs --quiet --scanners vuln,secret,misconfig --severity HIGH,CRITICAL --exit-code 0 \
  --format table --output "${REPORTS_DIR}/trivy-fs.txt" "${ROOT_DIR}"

for app in catalog-api orders-api; do
  image="$(image_ref "${app}")"
  log "Building ${image}"
  docker build -t "${image}" "${ROOT_DIR}/apps/${app}"

  log "Scanning image ${image}"
  trivy image --quiet --severity HIGH,CRITICAL --exit-code 0 \
    --format table --output "${REPORTS_DIR}/trivy-${app}.txt" "${image}"

  log "Pushing ${image}"
  docker push "${image}"
done

if [[ ! -f "${COSIGN_DIR}/cosign.key" || ! -f "${COSIGN_DIR}/cosign.pub" ]]; then
  log "Generating local Cosign keypair"
  COSIGN_PASSWORD="${COSIGN_PASSWORD:-lab-password}" \
    cosign generate-key-pair --output-key-prefix "${COSIGN_DIR}/cosign"
fi

for app in catalog-api orders-api; do
  image="$(image_ref "${app}")"
  log "Signing ${image}"
  COSIGN_PASSWORD="${COSIGN_PASSWORD:-lab-password}" \
    cosign sign --key "${COSIGN_DIR}/cosign.key" --allow-insecure-registry --yes "${image}"

  log "Verifying ${image}"
  cosign verify --key "${COSIGN_DIR}/cosign.pub" --allow-insecure-registry "${image}" \
    >"${REPORTS_DIR}/cosign-${app}.json"
done

log "Signing in-cluster image references for Kyverno verification"
publish_cosign_secret
for app in catalog-api orders-api; do
  run_cluster_cosign sign "${app}"
  run_cluster_cosign verify "${app}"
done

"${ROOT_DIR}/scripts/render.sh"

log "Running KubeSec manifest scan"
kubesec scan "${DIST_DIR}/rendered/apps.yaml" >"${REPORTS_DIR}/kubesec-apps.json" || true

log "Pipeline complete"
printf "Reports written to %s\n" "${REPORTS_DIR}"
