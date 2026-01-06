TF_DIR=infra/terraform

.PHONY: help init plan apply destroy fmt validate output

help:
	@echo "Targets: init, plan, apply, destroy, fmt, validate, output"

init:
	@if [ -z "$$TF_BACKEND_BUCKET" ]; then echo "TF_BACKEND_BUCKET is required"; exit 1; fi
	@if [ -z "$$TF_BACKEND_DYNAMODB_TABLE" ]; then echo "TF_BACKEND_DYNAMODB_TABLE is required"; exit 1; fi
	@KEY=$${TF_BACKEND_KEY:-$${TF_VAR_project_name:-jenkins}-$${TF_VAR_env:-env}/terraform.tfstate}; \
	REGION=$${TF_BACKEND_REGION:-$${AWS_REGION:-ap-south-1}}; \
	echo "Using remote backend: $$TF_BACKEND_BUCKET $$KEY $$TF_BACKEND_DYNAMODB_TABLE"; \
	terraform -chdir=$(TF_DIR) init \
	  -backend-config="bucket=$$TF_BACKEND_BUCKET" \
	  -backend-config="key=$$KEY" \
	  -backend-config="region=$$REGION" \
	  -backend-config="encrypt=true" \
	  -backend-config="dynamodb_table=$$TF_BACKEND_DYNAMODB_TABLE"

plan:
	terraform -chdir=$(TF_DIR) plan

apply:
	terraform -chdir=$(TF_DIR) apply -auto-approve

destroy:
	terraform -chdir=$(TF_DIR) destroy -auto-approve

fmt:
	terraform -chdir=$(TF_DIR) fmt

validate:
	terraform -chdir=$(TF_DIR) validate

output:
	terraform -chdir=$(TF_DIR) output
