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

# --- Checks (no cloud access) ----------------------------------------------

.PHONY: tf-check
tf-check: ## terraform fmt and validate (offline)
	terraform fmt -check -recursive infra
	terraform -chdir=$(BOOTSTRAP_DIR) init -backend=false -input=false >/dev/null
	terraform -chdir=$(BOOTSTRAP_DIR) validate

# --- CI ---------------------------------------------------------------------

.PHONY: aws-identity
aws-identity: ## Show the AWS identity of the current credentials
	aws sts get-caller-identity
