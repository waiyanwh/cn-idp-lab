#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT_DIR}/versions.env"

BIN_DIR="${ROOT_DIR}/bin"
LAB_DIR="${ROOT_DIR}/.lab"
REPORTS_DIR="${ROOT_DIR}/reports"
DIST_DIR="${ROOT_DIR}/dist"
COSIGN_DIR="${LAB_DIR}/cosign"
GITOPS_WORKDIR="${LAB_DIR}/gitops-workdir"
KIND_CONTEXT="kind-${KIND_CLUSTER_NAME}"

export PATH="${BIN_DIR}:${LAB_DIR}/venv/bin:${PATH}"

log() {
  printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"
}

die() {
  printf "error: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

check_docker() {
  need_cmd docker
  need_cmd timeout
  timeout --kill-after=2 5 docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || die "Docker daemon is not responding; start or restart Docker and rerun the command"
}

ensure_dirs() {
  mkdir -p "${BIN_DIR}" "${LAB_DIR}" "${REPORTS_DIR}" "${DIST_DIR}" "${COSIGN_DIR}"
}

lab_kubectl() {
  kubectl --context "${KIND_CONTEXT}" "$@"
}

lab_helm() {
  helm --kube-context "${KIND_CONTEXT}" "$@"
}

require_lab_tools() {
  local missing=0
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      printf "missing %s\n" "${tool}" >&2
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    die "run 'make tools' first"
  fi
}

wait_for_deployment() {
  local namespace="$1"
  local name="$2"
  local timeout="${3:-300s}"
  lab_kubectl -n "${namespace}" rollout status "deployment/${name}" --timeout="${timeout}"
}

wait_for_statefulset() {
  local namespace="$1"
  local name="$2"
  local timeout="${3:-300s}"
  local timeout_seconds="${timeout%s}"
  local waited=0
  while true; do
    local desired ready
    desired="$(lab_kubectl -n "${namespace}" get "statefulset/${name}" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
    ready="$(lab_kubectl -n "${namespace}" get "statefulset/${name}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
    desired="${desired:-1}"
    ready="${ready:-0}"
    if [[ "${ready}" == "${desired}" ]]; then
      printf "statefulset/%s ready=%s/%s\n" "${name}" "${ready}" "${desired}"
      return 0
    fi
    if [[ "${waited}" -ge "${timeout_seconds}" ]]; then
      lab_kubectl -n "${namespace}" get "statefulset/${name}" -o wide || true
      die "timed out waiting for StatefulSet ${namespace}/${name}"
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

wait_for_daemonset() {
  local namespace="$1"
  local name="$2"
  local timeout="${3:-300s}"
  lab_kubectl -n "${namespace}" rollout status "daemonset/${name}" --timeout="${timeout}"
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-120}"
  local waited=0
  until curl -fsS "${url}" >/dev/null 2>&1; do
    if [[ "${waited}" -ge "${timeout_seconds}" ]]; then
      die "timed out waiting for ${url}"
    fi
    sleep 2
    waited=$((waited + 2))
  done
}

wait_for_argocd_app() {
  local name="$1"
  local timeout_seconds="${2:-600}"
  local waited=0
  while true; do
    local sync health
    sync="$(lab_kubectl -n argocd get application "${name}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
    health="$(lab_kubectl -n argocd get application "${name}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
    if [[ "${sync}" == "Synced" && ( "${health}" == "Healthy" || "${health}" == "Progressing" || "${health}" == "Suspended" ) ]]; then
      printf "application/%s sync=%s health=%s\n" "${name}" "${sync}" "${health}"
      return 0
    fi
    if [[ "${waited}" -ge "${timeout_seconds}" ]]; then
      lab_kubectl -n argocd get application "${name}" -o wide || true
      die "timed out waiting for Argo CD application ${name}"
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

host_image_ref() {
  local app="$1"
  printf "localhost:%s/idp/%s:%s" "${LOCAL_REGISTRY_PORT}" "${app}" "${APP_VERSION}"
}

cluster_image_ref() {
  local app="$1"
  printf "%s/idp/%s:%s" "${CLUSTER_REGISTRY_HOST}" "${app}" "${APP_VERSION}"
}

image_ref() {
  host_image_ref "$1"
}
