SHELL := /usr/bin/env bash

ENV ?= dev
REGION ?= us-east-1
LIVE_ROOT := infrastructure/live
STACK_DIR := $(LIVE_ROOT)/$(ENV)/$(REGION)
VPC_DIR := $(STACK_DIR)/vpc
EC2_DIR := $(STACK_DIR)/ec2
K3S_DIR := $(STACK_DIR)/k3s

.PHONY: help check bootstrap init plan apply destroy vpc-plan vpc-apply ec2-plan ec2-apply k3s-plan k3s-apply outputs kubeconfig ssm platform-install platform-test platform-uninstall

help:
	@printf '%s\n' \
	  'Usage: make <target> [ENV=dev] [REGION=us-east-1]' \
	  '' \
	  'Infrastructure:' \
	  '  check              Verify required CLIs' \
	  '  bootstrap          Bootstrap the Terragrunt S3 backend' \
	  '  init               Initialize VPC, EC2 and K3s units' \
	  '  plan               Plan VPC -> EC2 -> K3s' \
	  '  apply              Apply VPC -> EC2 -> K3s' \
	  '  destroy            Destroy K3s -> EC2 -> VPC' \
	  '  vpc-plan           Plan only VPC' \
	  '  vpc-apply          Apply only VPC' \
	  '  ec2-plan           Plan only EC2' \
	  '  ec2-apply          Apply only EC2' \
	  '  k3s-plan           Plan only K3s configuration' \
	  '  k3s-apply          Apply only K3s configuration' \
	  '  outputs            Show EC2 and K3s outputs' \
	  '  kubeconfig         Retrieve kubeconfig through SSM' \
	  '  ssm                Open an SSM shell to the EC2 node' \
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
	cd $(EC2_DIR) && terragrunt init
	cd $(K3S_DIR) && terragrunt init

vpc-plan:
	cd $(VPC_DIR) && terragrunt plan

vpc-apply:
	cd $(VPC_DIR) && terragrunt apply

ec2-plan:
	cd $(EC2_DIR) && terragrunt plan

ec2-apply:
	cd $(EC2_DIR) && terragrunt apply

k3s-plan:
	cd $(K3S_DIR) && terragrunt plan

k3s-apply:
	cd $(K3S_DIR) && terragrunt apply

plan: vpc-plan ec2-plan k3s-plan

apply: vpc-apply ec2-apply k3s-apply

destroy:
	cd $(K3S_DIR) && terragrunt destroy
	cd $(EC2_DIR) && terragrunt destroy
	cd $(VPC_DIR) && terragrunt destroy

outputs:
	@echo '==> EC2 outputs'
	@cd $(EC2_DIR) && terragrunt output
	@echo '==> K3s outputs'
	@cd $(K3S_DIR) && terragrunt output

kubeconfig:
	ENV=$(ENV) REGION=$(REGION) ./scripts/kubeconfig.sh

ssm:
	cd $(EC2_DIR) && aws ssm start-session --region $(REGION) --target "$$(terragrunt output -raw instance_id)"

platform-install:
	./scripts/platform.sh install

platform-test:
	./scripts/platform.sh test

platform-uninstall:
	./scripts/platform.sh uninstall
