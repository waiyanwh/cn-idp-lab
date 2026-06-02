# Repository Guidelines

## Project Structure & Module Organization

This repo is a local CNCF internal developer platform lab. Sample services live in `apps/catalog-api/` and `apps/orders-api/`, each with a Python API, `tests/`, Dockerfile, and Helm chart under `chart/`. GitOps content is in `gitops/`: Argo CD `Application` objects in `gitops/argocd/`, platform policies in `gitops/platform/`, and app networking in `gitops/apps/`. Local cluster and reference IaC files are in `infra/kind/` and `infra/terraform/`. Bootstrap manifests are in `platform/bootstrap/`, demos in `demos/`, and repeatable automation in `scripts/`. Generated state belongs in `.lab/`, `bin/`, `dist/`, and `reports/`.

## Build, Test, and Development Commands

Use the Makefile from the repository root:

```sh
make tools     # install pinned local CLIs into ./bin and .lab/venv
make up        # create the registry, kind cluster, Gitea, and Argo CD
make pipeline  # test, scan, build, push, sign, verify, and render
make deploy    # seed Gitea and sync platform/apps through Argo CD
make verify    # run smoke tests and policy checks
make demos     # run safe learning demos
make lint      # run shell, Helm, Terraform, and render checks where available
make down      # remove local lab runtime state
```

## Coding Style & Naming Conventions

Keep YAML and Markdown indented with two spaces. Shell scripts must be executable, start with `#!/usr/bin/env bash`, and use `set -euo pipefail`. Prefer lowercase hyphenated names for manifests, charts, directories, and Kubernetes resources, for example `kyverno-policies` or `catalog-api`. Pin tool and chart versions in `versions.env` or the relevant Argo CD application instead of relying on `latest`.

## Testing Guidelines

Python tests use `pytest` and live under each service's `tests/` directory. Name tests for behavior, such as `test_health_returns_ok`. Run the full local validation path with `make lint`, `make pipeline`, and `make verify`. For manifest-only changes, also run `make render`; for demo changes, run `make demos` after the cluster is deployed.

## Commit & Pull Request Guidelines

There is no Git history in this workspace, so use Conventional Commits such as `feat: add kyverno policy demo` or `fix: pin loki single-binary mode`. Pull requests should include a short purpose statement, changed lab areas, validation commands with results, and screenshots or command output for dashboard, policy, or runtime-security changes.

## Security & Configuration Tips

Do not commit `.lab/`, `bin/`, `dist/`, `reports/`, Cosign keys, kubeconfigs, tokens, or Terraform state. Vault runs in dev mode and Cosign uses a generated local keypair for learning only; do not reuse either setup for production.
