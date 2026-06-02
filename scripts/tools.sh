#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib.sh"

install_binary() {
  local name="$1"
  local url="$2"
  local dest="${BIN_DIR}/${name}"
  local marker="${dest}.url"
  if [[ -x "${dest}" && -f "${marker}" && "$(cat "${marker}")" == "${url}" ]]; then
    log "${name} already exists at ${dest}"
    return
  fi
  log "Installing ${name}"
  curl -fsSL "${url}" -o "${dest}"
  chmod +x "${dest}"
  printf "%s" "${url}" >"${marker}"
}

install_from_tar() {
  local name="$1"
  local url="$2"
  local member="$3"
  local dest="${BIN_DIR}/${name}"
  local marker="${dest}.url"
  local tmp
  if [[ -x "${dest}" && -f "${marker}" && "$(cat "${marker}")" == "${url}" ]]; then
    log "${name} already exists at ${dest}"
    return
  fi
  tmp="$(mktemp -d)"
  log "Installing ${name}"
  curl -fsSL "${url}" -o "${tmp}/${name}.tar.gz"
  tar -xzf "${tmp}/${name}.tar.gz" -C "${tmp}"
  cp "${tmp}/${member}" "${dest}"
  chmod +x "${dest}"
  printf "%s" "${url}" >"${marker}"
  rm -rf "${tmp}"
}

ensure_dirs
need_cmd curl
need_cmd tar
need_cmd python3

[[ "$(uname -s)" == "Linux" ]] || die "this lab installer currently supports Linux only"
[[ "$(uname -m)" == "x86_64" ]] || die "this lab installer currently supports x86_64 only"

install_binary kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
install_binary kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
install_from_tar helm "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" "linux-amd64/helm"
install_binary argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
install_binary cosign "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64"
install_from_tar trivy "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_Linux-64bit.tar.gz" "trivy"
install_from_tar kubesec "https://github.com/controlplaneio/kubesec/releases/download/${KUBESEC_VERSION}/kubesec_linux_amd64.tar.gz" "kubesec"

if [[ ! -x "${LAB_DIR}/venv/bin/bandit" ]]; then
  log "Installing Bandit ${BANDIT_VERSION}"
  python3 -m venv "${LAB_DIR}/venv"
  "${LAB_DIR}/venv/bin/pip" install --upgrade pip >/dev/null
  "${LAB_DIR}/venv/bin/pip" install "bandit==${BANDIT_VERSION}" >/dev/null
fi

log "Installed lab tools"
kind version
kubectl version --client=true
helm version --short
argocd version --client --short
cosign version | sed -n '1,3p'
trivy --version | sed -n '1p'
kubesec version || true
bandit --version
