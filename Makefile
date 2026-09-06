SHELL := /usr/bin/env bash

ENV ?= dev
REGION ?= us-east-1
LIVE_ROOT := infrastructure/live
STACK_DIR := $(LIVE_ROOT)/$(ENV)/$(REGION)
VPC_DIR := $(STACK_DIR)/vpc
K3S_DIR := $(STACK_DIR)/k3s

.PHONY: help check bootstrap init plan apply destroy vpc-plan vpc-apply k3s-plan k3s-apply outputs kubeconfig ssm platform-install platform-test platform-uninstall

help:
	@printf '%s\n' \
	  'Usage: make <target> [ENV=dev] [REGION=us-east-1]' \
	  '' \
	  'Infrastructure:' \
	  '  check              Verify required CLIs' \
	  '  bootstrap          Bootstrap the Terragrunt S3 backend' \
	  '  init               Initialize VPC and K3s units' \
	  '  plan               Plan VPC then K3s' \
	  '  apply              Apply VPC then K3s' \
	  '  destroy            Destroy K3s then VPC' \
	  '  vpc-plan           Plan only VPC' \
	  '  vpc-apply          Apply only VPC' \
	  '  k3s-plan           Plan only K3s' \
	  '  k3s-apply          Apply only K3s' \
	  '  outputs            Show K3s Terraform outputs' \
	  '  kubeconfig         Retrieve kubeconfig through SSM' \
	  '  ssm                Open an SSM shell to the K3s node' \
	  '' \
	  'Platform:' \
	  '  platform-install   Install Traefik, cert-manager, Argo CD' \
	  '  platform-test      Run platform smoke tests' \
	  '  platform-uninstall Uninstall platform in reverse order'

check:
	@for cmd in aws terraform terragrunt kubectl helm curl git; do \
		command -v $$cmd >/dev/null || { echo "ERROR: $$cmd is required"; exit 1; }; \
	done
	@echo 'All required CLIs are available.'

bootstrap:
	cd $(VPC_DIR) && terragrunt backend bootstrap

init:
	cd $(VPC_DIR) && terragrunt init
	cd $(K3S_DIR) && terragrunt init

vpc-plan:
	cd $(VPC_DIR) && terragrunt plan

vpc-apply:
	cd $(VPC_DIR) && terragrunt apply

k3s-plan:
	cd $(K3S_DIR) && terragrunt plan

k3s-apply:
	cd $(K3S_DIR) && terragrunt apply

plan: vpc-plan k3s-plan

apply: vpc-apply k3s-apply

destroy:
	cd $(K3S_DIR) && terragrunt destroy
	cd $(VPC_DIR) && terragrunt destroy

outputs:
	cd $(K3S_DIR) && terragrunt output

kubeconfig:
	ENV=$(ENV) REGION=$(REGION) ./scripts/kubeconfig.sh

ssm:
	cd $(K3S_DIR) && aws ssm start-session --region $(REGION) --target "$$(terragrunt output -raw instance_id)"

platform-install:
	./scripts/platform.sh install

platform-test:
	./scripts/platform.sh test

platform-uninstall:
	./scripts/platform.sh uninstall
