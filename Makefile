.EXPORT_ALL_VARIABLES:
.ONESHELL:
.PHONY: apply destroy plan prep fmt docs help check-env check-dirs force-init force-unlock console test module-test cloud-init-test

# Multi-step recipes are chained on one shell line (&&, ;) so they behave the
# same under GNU make 3.81 (macOS, no .ONESHELL) and 4.x.
SHELL           := /bin/bash

# ---------------------------------------------------------------------------
# Inputs
#   ENVIRONMENT  (required)  e.g. dev, staging, prod
#   LOCATION     Hetzner location, default fsn1 (fsn1, nbg1, hel1, ash, hil, sin)
#   TF_DIR       OpenTofu root to run in, default examples/complete
#   HCLOUD_TOKEN (required, env only) Hetzner Cloud API token
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (env only) Object Storage creds
#                for the S3 backend (ADR-0006)
#
# Variables passed to the root module: -var=location=$(LOCATION)
# and -var=environment=$(ENVIRONMENT). The root in TF_DIR must declare both.
# ---------------------------------------------------------------------------
LOCATION        ?= fsn1
ENVIRONMENT     ?=
TF_DIR          ?= examples/complete
PARAMS_DIR       = params/$(LOCATION)/$(ENVIRONMENT)
VARS             = $(PARAMS_DIR)/params.tfvars
BACKEND_CONFIG   = $(PARAMS_DIR)/backend.hcl
FEATURES_DIR    ?= tests/compliance/features
TOFU_BIN        := $(shell command -v tofu 2>/dev/null || command -v terraform 2>/dev/null)
TERRAFORM_DOCS  := $(shell command -v terraform-docs 2>/dev/null)
TF_COMPLIANCE   := $(shell command -v terraform-compliance 2>/dev/null)
FORCE           ?= 0
CONFIRM         ?=
# State locking via S3 conditional writes (use_lockfile, OpenTofu >= 1.10).
# Hetzner Object Storage support for If-None-Match is UNVERIFIED; if locking
# fails, run with LOCK=false and rely on the CI concurrency group instead.
LOCK            ?= true

TOFU             = $(TOFU_BIN) -chdir=$(TF_DIR)
TF_VARS          = -var="location=$(LOCATION)" \
                   -var="environment=$(ENVIRONMENT)" \
                   -var-file="$(abspath $(VARS))"

# Local-backend override used only by `make test`; removed on exit.
COMPLIANCE_OVERRIDE = $(TF_DIR)/zz_compliance_backend_override.tf
COMPLIANCE_PLAN     = compliance.plan
COMPLIANCE_JSON     = $(abspath $(TF_DIR))/compliance.plan.json
# Features tagged @tofu-test are specifications executed by `tofu test`
# (module-test); terraform-compliance (radish tag expression) skips them.
COMPLIANCE_TAGS     ?= not tofu-test
MODULE_DIR          ?= modules/kafka-cluster

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

check-env:
	@[ -n "$(ENVIRONMENT)" ] || { printf '\033[0;31mENVIRONMENT is not set\033[0m\n'; exit 1; }
	@[ -n "$${HCLOUD_TOKEN:-}" ] || { printf '\033[0;31mHCLOUD_TOKEN is not set\033[0m\n'; exit 1; }
	@[ -n "$(TOFU_BIN)" ] || { printf '\033[0;31mNeither tofu nor terraform found\033[0m\n'; exit 1; }

check-dirs: check-env
	@[ -d "$(TF_DIR)" ] || { printf '\033[0;31mTF_DIR $(TF_DIR) does not exist\033[0m\n'; exit 1; }
	@[ -f "$(VARS)" ] || { printf '\033[0;31m$(VARS) not found (copy params.tfvars.example)\033[0m\n'; exit 1; }

force-init:
	@if [ $(FORCE) -gt 0 ]; then rm -rf "$(TF_DIR)/.terraform"; fi

prep: check-dirs force-init ## Initialise S3 backend (Hetzner Object Storage)
	@[ -f "$(BACKEND_CONFIG)" ] || { printf '\033[0;31m$(BACKEND_CONFIG) not found (copy backend.hcl.example)\033[0m\n'; exit 1; }
	@rm -f "$(COMPLIANCE_OVERRIDE)"
	@$(TOFU) init \
		-reconfigure \
		-backend=true \
		-backend-config="$(abspath $(BACKEND_CONFIG))" \
		-input=false

plan: prep ## Show what will change (exit 0/2 = ok, 1 = error)
	@echo "Using vars from $(VARS)"
	@EXIT_CODE=0; \
	$(TOFU) plan \
		-detailed-exitcode \
		-out=plan.out \
		-lock=$(LOCK) \
		-input=false \
		-refresh=true \
		$(TF_VARS) $(EXTRA_OPTS) || EXIT_CODE=$$?; \
	echo "Plan exited with status $$EXIT_CODE"; \
	echo $$EXIT_CODE > tf_exit_code; \
	[ $$EXIT_CODE -ne 1 ]

apply: check-env check-dirs ## Apply the saved plan from make plan (costs money)
	@[ -f "$(TF_DIR)/plan.out" ] || { printf '\033[0;31mNo saved plan: run make plan first\033[0m\n'; exit 1; }; \
	$(TOFU) apply \
		-lock=$(LOCK) \
		-input=false \
		plan.out && rm -f "$(TF_DIR)/plan.out"

destroy: ## Destroy all resources (DANGEROUS, requires CONFIRM=yes)
	@[ "$(CONFIRM)" = "yes" ] || { printf '\033[0;31mRefusing to destroy: re-run with CONFIRM=yes\033[0m\n'; exit 1; }; \
	$(MAKE) --no-print-directory prep && \
	$(TOFU) destroy \
		-lock=$(LOCK) \
		-input=false \
		-refresh=true \
		$(TF_VARS) $(EXTRA_OPTS)

console: prep ## Launch interactive console
	@$(TOFU) console $(TF_VARS)

force-unlock: prep ## Force-unlock state (TF_FORCE_UNLOCK=<id>)
	@$(TOFU) force-unlock $(TF_FORCE_UNLOCK)

test: check-dirs ## Run terraform-compliance against a plan (local backend, -refresh=false)
	@[ -d "$(FEATURES_DIR)" ] || { printf '\033[0;31m$(FEATURES_DIR) does not exist\033[0m\n'; exit 1; }
	@[ -n "$(TF_COMPLIANCE)" ] || { printf '\033[0;31mterraform-compliance not found (pip install terraform-compliance)\033[0m\n'; exit 1; }
	@if ! grep -L '@tofu-test' $(FEATURES_DIR)/*.feature 2>/dev/null | grep -q .; then \
		echo "No terraform-compliance features (all tagged @tofu-test); skipping"; exit 0; fi; \
	trap 'rm -f "$(COMPLIANCE_OVERRIDE)"' EXIT; \
	printf 'terraform {\n  backend "local" {}\n}\n' > "$(COMPLIANCE_OVERRIDE)" && \
	$(TOFU) init -reconfigure -input=false && \
	$(TOFU) plan \
		-refresh=false \
		-lock=false \
		-input=false \
		-out=$(COMPLIANCE_PLAN) \
		$(TF_VARS) $(EXTRA_OPTS) && \
	$(TOFU) show -json $(COMPLIANCE_PLAN) > "$(COMPLIANCE_JSON)" && \
	$(TF_COMPLIANCE) -p "$(COMPLIANCE_JSON)" -f "$(FEATURES_DIR)" --tags "$(COMPLIANCE_TAGS)"

module-test: ## Run native tofu test suites for the module (plan-only, mocked provider)
	@$(TOFU_BIN) -chdir=$(MODULE_DIR) init -backend=false -input=false && \
	$(TOFU_BIN) -chdir=$(MODULE_DIR) test

cloud-init-test: ## Test the cloud-init volume mount script with stubbed blkid/mkfs/mount (no root)
	@sh tests/cloud-init/test_mount_data_volume.sh

fmt: ## Format all .tf files
	@$(TOFU_BIN) fmt -recursive

docs: ## Inject inputs/outputs into module README with terraform-docs
	@[ "$(TERRAFORM_DOCS)" ] || { echo "terraform-docs not found"; exit 1; }
	@$(TERRAFORM_DOCS) markdown table --output-file README.md --output-mode inject $(MODULE_DIR)
