.EXPORT_ALL_VARIABLES:
.ONESHELL:
.PHONY: apply destroy plan prep fmt docs help check-env force-unlock console

REGION          ?= eu-west-2
ENVIRONMENT     ?=
VARS             = params/$(REGION)/$(ENVIRONMENT)/params.tfvars
TOFU_BIN        := $(shell command -v tofu 2>/dev/null || command -v terraform 2>/dev/null)
TERRAFORM_DOCS  := $(shell command -v terraform-docs 2>/dev/null)
FORCE           ?= 0

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-env:
	@[ "$(ENVIRONMENT)" ] || { echo "\033[0;31mENVIRONMENT is not set\033[0m"; exit 1; }
	@[ "$(TOFU_BIN)" ]    || { echo "\033[0;31mNeither tofu nor terraform found\033[0m"; exit 1; }

force-init:
	@if [ $(FORCE) -gt 0 ]; then rm -rf .terraform; fi

prep: check-env force-init ## Initialise backend
	@$(TOFU_BIN) init \
		-backend=true \
		-input=false

plan: prep ## Show what will change
	@echo "Using vars from $(VARS)"
	@$(TOFU_BIN) plan \
		-detailed-exitcode \
		-out=plan.out \
		-lock=true \
		-input=false \
		-refresh=true \
		-var="region=$(REGION)" \
		-var="env=$(ENVIRONMENT)" \
		-var-file="$(VARS)" $(EXTRA_OPTS); \
		EXIT_CODE=$$?; \
		echo "Plan exited with status $$EXIT_CODE"; \
		echo $$EXIT_CODE > tf_exit_code

apply: prep ## Apply the plan (costs money)
	@$(TOFU_BIN) apply \
		-lock=true \
		-input=false \
		-refresh=true \
		-var="region=$(REGION)" \
		-var="env=$(ENVIRONMENT)" \
		-var-file="$(VARS)" $(EXTRA_OPTS)

destroy: prep ## Destroy all resources (DANGEROUS)
	@$(TOFU_BIN) destroy \
		-lock=true \
		-input=false \
		-refresh=true \
		-var="region=$(REGION)" \
		-var="env=$(ENVIRONMENT)" \
		-var-file="$(VARS)" $(EXTRA_OPTS)

console: prep ## Launch interactive console
	@$(TOFU_BIN) console \
		-var="region=$(REGION)" \
		-var="env=$(ENVIRONMENT)" \
		-var-file="$(VARS)"

force-unlock: prep ## Force-unlock state (TF_FORCE_UNLOCK=<id>)
	@$(TOFU_BIN) force-unlock $(TF_FORCE_UNLOCK)

fmt: ## Format all .tf files
	@$(TOFU_BIN) fmt -recursive

docs: ## Generate module README with terraform-docs
	@[ "$(TERRAFORM_DOCS)" ] || { echo "terraform-docs not found"; exit 1; }
	@$(TERRAFORM_DOCS) markdown table . > README.md
