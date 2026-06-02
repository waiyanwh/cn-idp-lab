SHELL := /usr/bin/env bash

.PHONY: tools up pipeline platform deploy verify demos down lint render help

help:
	@printf "Targets:\n"
	@printf "  make tools     Install repo-local lab CLIs into ./bin and .lab/venv\n"
	@printf "  make up        Create registry, kind cluster, Calico, Gitea, and Argo CD\n"
	@printf "  make pipeline  Test, scan, build, sign, verify, and push app images\n"
	@printf "  make deploy    Seed Gitea GitOps repo, sync Argo CD, configure Vault\n"
	@printf "  make verify    Run cluster smoke tests and policy checks\n"
	@printf "  make demos     Print and run safe demo checks for the learning labs\n"
	@printf "  make render    Render app Helm charts locally\n"
	@printf "  make lint      Run available static checks\n"
	@printf "  make down      Delete the local kind lab and generated state\n"

tools:
	./scripts/tools.sh

up:
	./scripts/up.sh

pipeline:
	./scripts/pipeline.sh

platform deploy:
	./scripts/deploy.sh

verify:
	./scripts/verify.sh

demos:
	./scripts/demos.sh

down:
	./scripts/down.sh

render:
	./scripts/render.sh

lint:
	./scripts/lint.sh

