# Cloud Native Internal Developer Platform Lab

This repository turns the CNCF blog post [Building a Cloud Native Internal Developer Platform with Kubernetes, GitOps and Supply Chain Security](https://www.cncf.io/blog/2026/05/29/building-a-cloud-native-internal-developer-platform-with-kubernetes-gitops-and-supply-chain-security/) into a local, hands-on lab. It uses Docker, kind, Argo CD, Gitea, Istio, Kyverno, Cosign, Trivy, KubeSec, Prometheus, Grafana, Loki, Falco, Vault, and Secrets Store CSI.

The lab is local-only. It uses an in-cluster Gitea repository instead of GitHub and a generated local Cosign keypair instead of cloud OIDC so every learner can reproduce the same setup.

## What You Build

| Blog topic | Local lab implementation |
| --- | --- |
| Kubernetes platform foundation | kind cluster with Calico CNI and NetworkPolicy |
| GitOps control plane | Argo CD syncing from in-cluster Gitea |
| App delivery | Two Python services packaged as containers and Helm charts |
| CI/CD security gates | Unit tests, Bandit, Trivy, KubeSec, Cosign sign/verify |
| Admission control | Kyverno policies for image tags, pod security, signature audit |
| Service mesh | Istio gateway, VirtualServices, and mTLS demo |
| Observability | Prometheus, Grafana, Loki, and Promtail |
| Runtime security | Falco plus RuntimeDefault seccomp demo |
| Secret management | Vault dev server mounted through Secrets Store CSI |
| Rollback and drift | Argo CD self-heal and Git rollback workflow |

## Prerequisites

Required on the host:

```sh
docker --version
git --version
make --version
python3 --version
curl --version
```

The lab installs pinned repo-local CLIs into `./bin`, so your system `kubectl`, `helm`, `kind`, `trivy`, `cosign`, and `kubesec` versions do not need to match.

Recommended host capacity: 4 CPUs, 8 GB RAM, and 15 GB free disk.

## Repository Layout

```text
apps/                 Sample services and Helm charts
demos/                Hands-on policy, mTLS, Falco, and seccomp demos
gitops/               Content pushed into in-cluster Gitea
infra/kind/           Declarative kind cluster config
infra/terraform/      Local IaC reference for kind
platform/bootstrap/   Bootstrap manifests for Gitea and Argo CD
scripts/              Repeatable setup, pipeline, deploy, verify, cleanup
versions.env          Pinned lab versions
```

Generated files are written to `.lab/`, `bin/`, `dist/`, and `reports/`.

## Quick Start

Run each step from the repository root.

### 1. Install Repo-Local Tools

```sh
make tools
```

Installs pinned versions from `versions.env` into `./bin` and installs Bandit into `.lab/venv`.

### 2. Create the Cluster and Bootstrap GitOps

```sh
make up
```

This starts a local Docker registry on `127.0.0.1:5001`, exposes it inside Kubernetes as `registry.kube-system.svc.cluster.local:5001`, creates a kind cluster named `cncf-idp`, installs Calico, deploys Gitea, creates the Gitea admin user, and installs Argo CD.

### 3. Run the Supply Chain Pipeline

```sh
make pipeline
```

This runs unit tests, Bandit SAST, Trivy filesystem and image scans, Docker builds, registry pushes, Cosign signing, Cosign verification, Helm rendering, and KubeSec scans. Images are pushed from the host through `localhost:5001` and also signed by an in-cluster Cosign job using the registry service name Kyverno can reach.

Reports are stored in `reports/`.

### 4. Deploy the Platform and Apps

```sh
make deploy
```

This seeds the in-cluster Gitea repo, applies the Argo CD root app, installs platform components, configures Vault Kubernetes auth, and deploys `catalog-api` and `orders-api`.

### 5. Verify the Lab

```sh
make verify
```

Expected results:

```sh
curl http://localhost:8080/catalog
curl http://localhost:8080/orders
```

Both responses should show a `secret_message` value loaded from Vault through Secrets Store CSI.

## Access Dashboards

Argo CD:

```sh
kubectl --context kind-cncf-idp -n argocd port-forward svc/argocd-server 8081:80
```

Open `http://localhost:8081`. The initial admin password is available with:

```sh
kubectl --context kind-cncf-idp -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Grafana:

```sh
kubectl --context kind-cncf-idp -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Open `http://localhost:3000`. The username is `admin`; get the password with:

```sh
kubectl --context kind-cncf-idp -n observability get secret kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## Learning Demos

Run the safe demo suite:

```sh
make demos
```

Or run individual demos.

Kyverno rejects mutable image tags:

```sh
kubectl --context kind-cncf-idp apply --dry-run=server -f demos/kyverno-latest-blocked.yaml
```

Argo CD self-heals drift:

```sh
kubectl --context kind-cncf-idp -n apps scale deploy/catalog-api --replicas=0
kubectl --context kind-cncf-idp -n argocd get app catalog-api -w
```

Istio strict mTLS:

```sh
kubectl --context kind-cncf-idp apply -f demos/strict-mtls.yaml
curl http://localhost:8080/catalog
kubectl --context kind-cncf-idp apply -f gitops/apps/networking/peer-authentication.yaml
```

NetworkPolicy denial:

```sh
kubectl --context kind-cncf-idp apply -f demos/network-denied.yaml
kubectl --context kind-cncf-idp -n blocked-client wait \
  --for=jsonpath='{.status.phase}'=Succeeded pod/blocked-client --timeout=60s
kubectl --context kind-cncf-idp -n blocked-client logs pod/blocked-client
kubectl --context kind-cncf-idp delete -f demos/network-denied.yaml --wait=false
```

Falco runtime alert:

```sh
kubectl --context kind-cncf-idp apply -f demos/falco-trigger.yaml
kubectl --context kind-cncf-idp -n falco logs ds/falco --tail=30
kubectl --context kind-cncf-idp delete -f demos/falco-trigger.yaml
```

## Rollback Exercise

The GitOps source is seeded into Gitea from `gitops/` plus the app Helm charts. To simulate rollback:

1. Change `apps/catalog-api/chart/values.yaml`, for example `replicaCount: 1`.
2. Run `make deploy`.
3. Watch Argo CD reconcile `catalog-api`.
4. Revert the file locally.
5. Run `make deploy` again.

This demonstrates Git as the deployment source of truth.

## Validation Commands

```sh
make lint
make render
make pipeline
make verify
```

`make lint` checks shell syntax, runs ShellCheck when installed, lints Helm charts, validates the Terraform reference when Terraform is installed, and renders app manifests.

## Cleanup

```sh
make down
```

This deletes the kind cluster, removes the local registry container, and deletes generated `.lab/`, `dist/`, and `reports/` state. It does not delete source files.

## Notes and Local Deviations

- Gitea replaces a hosted Git provider so the GitOps loop is fully local.
- The local Cosign keypair replaces cloud keyless OIDC. Keys are generated in `.lab/cosign/` and ignored by Git.
- The local registry has two names: `localhost:5001` for host Docker/Cosign and `registry.kube-system.svc.cluster.local:5001` for Kubernetes pulls and Kyverno verification.
- Vault runs in dev mode for learning only. Do not reuse this configuration for production.
- The Terraform directory is a local IaC reference; the working cluster path uses the declarative kind config in `infra/kind/cluster.yaml`.
- All production-style secrets, signing keys, scan reports, and generated Git worktrees are excluded from Git.
