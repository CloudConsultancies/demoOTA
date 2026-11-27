# Single entry point for local work and CI. CI calls these targets and
# does not repeat their logic in workflow YAML.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# --- AWS bootstrap (applied once, locally, by a human; never from CI) ------
# The account is shared with demoKubernetesCluster; the CLI profile is
# that project's (see .claude/CLAUDE.md > Environment).
BOOTSTRAP_DIR     := infra/bootstrap
BOOTSTRAP_PROFILE ?= demo-k8s
BOOTSTRAP_TF       = AWS_PROFILE=$(BOOTSTRAP_PROFILE) terraform -chdir=$(BOOTSTRAP_DIR)
# Evaluated only when used: demo-ota-tfstate-<account ID>
TFSTATE_BUCKET    ?= demo-ota-tfstate-$(shell AWS_PROFILE=$(BOOTSTRAP_PROFILE) aws sts get-caller-identity --query Account --output text)

.PHONY: help
help: ## List the targets
	@grep -hE '^[a-z0-9-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-20s %s\n", $$1, $$2}'

.PHONY: bootstrap-local
bootstrap-local: ## First apply only: use local state until the bucket exists
	printf 'terraform {\n  backend "local" {}\n}\n' > $(BOOTSTRAP_DIR)/backend_override.tf

.PHONY: bootstrap-init
bootstrap-init: ## terraform init of the bootstrap (S3 backend, or local with the override)
	@if [ -f $(BOOTSTRAP_DIR)/backend_override.tf ]; then \
	  $(BOOTSTRAP_TF) init; \
	else \
	  $(BOOTSTRAP_TF) init -backend-config="bucket=$(TFSTATE_BUCKET)"; \
	fi

# The plan is saved (tfplan, git-ignored) and bootstrap-apply applies
# exactly that plan, nothing re-planned. Terraform refuses a saved plan
# that is stale (state changed since), so re-run bootstrap-plan then.
.PHONY: bootstrap-plan
bootstrap-plan: ## terraform plan of the bootstrap, saved for bootstrap-apply
	$(BOOTSTRAP_TF) plan -out=tfplan

.PHONY: bootstrap-validate
bootstrap-validate: ## Check the saved plan's IAM policies with IAM Access Analyzer (read-only)
	AWS_PROFILE=$(BOOTSTRAP_PROFILE) scripts/validate-iam-policies.sh $(BOOTSTRAP_DIR) tfplan

.PHONY: bootstrap-apply
bootstrap-apply: ## Apply exactly the plan saved by bootstrap-plan
	@[ -f $(BOOTSTRAP_DIR)/tfplan ] || { echo "No saved plan: run make bootstrap-plan first and review it."; exit 1; }
	$(BOOTSTRAP_TF) apply tfplan
	rm -f $(BOOTSTRAP_DIR)/tfplan

.PHONY: bootstrap-migrate
bootstrap-migrate: ## Move the local bootstrap state into the bucket (after the first apply)
	rm -f $(BOOTSTRAP_DIR)/backend_override.tf
	$(BOOTSTRAP_TF) init -migrate-state -backend-config="bucket=$(TFSTATE_BUCKET)"

.PHONY: bootstrap-outputs
bootstrap-outputs: ## Show the values to store as GitHub repository variables
	$(BOOTSTRAP_TF) output github_variables

# Reads the outputs (from the S3 state, hence the profile) and stores
# each one as a GitHub Actions repository variable of this repo.
.PHONY: bootstrap-github-vars
bootstrap-github-vars: ## Store the bootstrap outputs as GitHub repository variables
	@set -o pipefail; vars=$$($(BOOTSTRAP_TF) output -json github_variables) || exit 1; \
	jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$$vars" \
	  | while read -r key value; do gh variable set "$$key" --body "$$value"; done
	gh variable list

# --- Infrastructure stacks (planned and applied by CI) ---------------------
# CI calls these with the OIDC role credentials in the environment and
# AWS_TFSTATE_BUCKET set from the repository variable. Locally, run them
# with AWS_PROFILE=demo-k8s (a human only; plan is read-only).
STACK     ?= storage
INFRA_DIR  = infra/$(STACK)
INFRA_TF   = terraform -chdir=$(INFRA_DIR)
# CI sets AWS_TFSTATE_BUCKET; locally it is derived like the bootstrap's
AWS_TFSTATE_BUCKET ?= $(TFSTATE_BUCKET)
PLAN_SUMMARY       = $(INFRA_DIR)/plan-summary.md

.PHONY: infra-init
infra-init: ## terraform init of STACK (default: storage) with the S3 backend
	$(INFRA_TF) init -input=false -backend-config="bucket=$(AWS_TFSTATE_BUCKET)"

# Saves the plan (tfplan, git-ignored) and a Markdown summary of it
# (plan-summary.md, git-ignored) for the pull request comment.
.PHONY: infra-plan
infra-plan: infra-init ## terraform plan of STACK, saved for infra-apply
	$(INFRA_TF) plan -input=false -lock-timeout=5m -out=tfplan
	scripts/plan-summary.sh $(INFRA_DIR) tfplan $(STACK) > $(PLAN_SUMMARY)

.PHONY: infra-apply
infra-apply: ## Apply exactly the plan saved by infra-plan
	@[ -f $(INFRA_DIR)/tfplan ] || { echo "No saved plan: run make infra-plan first."; exit 1; }
	$(INFRA_TF) apply -input=false -lock-timeout=5m tfplan
	rm -f $(INFRA_DIR)/tfplan

# Needs GH_TOKEN (pull-requests: write) and PR, the pull request number.
# One comment per stack, updated on every push.
.PHONY: infra-plan-comment
infra-plan-comment: ## Post the plan summary of STACK to pull request PR
	@[ -n "$(PR)" ] || { echo "Set PR=<pull request number>."; exit 1; }
	@[ -f $(PLAN_SUMMARY) ] || { echo "No plan summary: run make infra-plan first."; exit 1; }
	scripts/pr-comment.sh "$(PR)" "<!-- infra-plan:$(STACK) -->" $(PLAN_SUMMARY)

# --- Storage stack: steps a human runs locally ------------------------------
STORAGE_TF = AWS_PROFILE=$(BOOTSTRAP_PROFILE) terraform -chdir=infra/storage

# Reads the outputs (from the S3 state, hence the profile) and stores
# each one as a GitHub Actions repository variable of this repo. The
# names are fixed, so this is needed once after the first apply.
.PHONY: storage-github-vars
storage-github-vars: ## Store the storage bucket names as GitHub repository variables
	$(STORAGE_TF) init -input=false -backend-config="bucket=$(TFSTATE_BUCKET)" >/dev/null
	@set -o pipefail; vars=$$($(STORAGE_TF) output -json github_variables) || exit 1; \
	jq -r 'to_entries[] | "\(.key) \(.value)"' <<<"$$vars" \
	  | while read -r key value; do gh variable set "$$key" --body "$$value"; done
	gh variable list

# Teardown after a demo. Only the cache goes: artifacts and records are
# kept on purpose (prevent_destroy). Terraform shows the plan and asks
# for confirmation. The next infra-apply on main creates the cache again.
.PHONY: storage-destroy-cache
storage-destroy-cache: ## Destroy the cache bucket and its contents (asks first)
	$(STORAGE_TF) init -input=false -backend-config="bucket=$(TFSTATE_BUCKET)" >/dev/null
	$(STORAGE_TF) destroy -target=aws_s3_bucket.cache

# --- Checks (no cloud access) ----------------------------------------------
# Own data directory (.terraform-check, git-ignored): a stack already
# initialised with the S3 backend would otherwise need credentials.

TF_STACKS := $(BOOTSTRAP_DIR) infra/storage

.PHONY: tf-check
tf-check: ## terraform fmt and validate of every stack (offline)
	terraform fmt -check -recursive infra
	@set -e; for dir in $(TF_STACKS); do \
	  echo "validate $$dir"; \
	  TF_DATA_DIR=.terraform-check terraform -chdir=$$dir init -backend=false -input=false >/dev/null; \
	  TF_DATA_DIR=.terraform-check terraform -chdir=$$dir validate; \
	done

# --- CI ---------------------------------------------------------------------

.PHONY: aws-identity
aws-identity: ## Show the AWS identity of the current credentials
	aws sts get-caller-identity
