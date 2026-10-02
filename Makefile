SHELL := /bin/bash

PACKAGE ?= auth-stack
# Default XRD_DIR for legacy single-API targets; multi-API targets derive per-example.
XRD_DIR := apis/authstacks
COMPOSITION := $(XRD_DIR)/composition.yaml
DEFINITION := $(XRD_DIR)/definition.yaml
EXAMPLE_DEFAULT := examples/authstacks/standard.yaml
RENDER_TESTS := $(wildcard tests/test-*)
E2E_TESTS := $(wildcard tests/e2etest-*)

# Multi-API support: examples/<apiplural>/<example>.yaml maps to apis/<apiplural>/.
# Helper macro: api_dir_for(example_path) → apis/<dirname>
api-dir = apis/$(word 2,$(subst /, ,$(1)))

clean:
	rm -rf _output
	rm -rf .up

build:
	up project build

# Examples list - mirrors GitHub Actions workflow
# Format: example_path::observed_resources_path (observed_resources_path is optional)
# api_path is derived from example_path via the api-dir macro (examples/<x>/... → apis/<x>/).
EXAMPLES := \
    examples/authstacks/minimal.yaml:: \
    examples/authstacks/standard.yaml:: \
    examples/authstacks/local-colima.yaml:: \
    examples/authstacks/with-smtp.yaml:: \
    examples/authstacks/with-instance.yaml:: \
    examples/machineusers/minimal.yaml:: \
    examples/machineusers/with-pat.yaml:: \
    examples/machineusers/with-pat-push.yaml:: \
    examples/humanusers/explicit-org.yaml:: \
    examples/humanusers/with-org-ref.yaml:: \
    examples/oidcclients/storybook-preview.yaml:: \
    examples/oidcclients/storybook-preview.yaml::tests/test-oidcclient/observed/ready.yaml \
    examples/grants/referenced-same-org.yaml:: \
    examples/grants/same-org.yaml:: \
    examples/grants/cross-org.yaml:: \
    examples/grants/cross-org.yaml::tests/test-grant/observed/cross-org-iter2.yaml

# Render serially: up updates shared project metadata/schema caches during build.
render\:all:
	@set -e; \
	for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; observed=$${entry#*::}; \
		api_dir=$$(echo "$$example" | awk -F/ '{print "apis/" $$2}'); \
		echo "Rendering $$example"; \
		if [ -n "$$observed" ]; then \
			up composition render --xrd=$$api_dir/definition.yaml $$api_dir/composition.yaml $$example --observed-resources=$$observed; \
		else \
			up composition render --xrd=$$api_dir/definition.yaml $$api_dir/composition.yaml $$example; \
		fi; \
	done

# Include dependency metadata and all XRDs when loading validation schemas.
.PHONY: generate-configuration
generate-configuration:
	hops validate generate-configuration --path . --api-path $(XRD_DIR) --no-gitignore-update

validate\:all: generate-configuration
	@set -e -o pipefail; \
	for entry in $(EXAMPLES); do \
		example=$${entry%%::*}; observed=$${entry#*::}; \
		api_dir=$$(echo "$$example" | awk -F/ '{print "apis/" $$2}'); \
		echo "Validating $$example"; \
		if [ -n "$$observed" ]; then \
			up composition render --xrd=$$api_dir/definition.yaml $$api_dir/composition.yaml $$example --observed-resources=$$observed --include-full-xr --quiet; \
		else \
			up composition render --xrd=$$api_dir/definition.yaml $$api_dir/composition.yaml $$example --include-full-xr --quiet; \
		fi | crossplane resource validate apis --error-on-missing-schemas -; \
	done

# Shorthand aliases
.PHONY: clean build test e2e publish render validate
render: ; @$(MAKE) 'render:all'
validate: ; @$(MAKE) 'validate:all'

# Single example targets (legacy — uses default XRD_DIR for examples/authstacks/<name>.yaml)
render\:%:
	@example="examples/authstacks/$*.yaml"; \
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example

validate\:%:
	@example="examples/authstacks/$*.yaml"; \
	up composition render --xrd=$(DEFINITION) $(COMPOSITION) $$example \
		--include-full-xr --quiet | \
		crossplane resource validate $(XRD_DIR) --error-on-missing-schemas -

test:
	up test run $(RENDER_TESTS)

# Native observation readiness and migration regressions; requires PyYAML.
.PHONY: test-security
test-security:
	python3 -m unittest discover -s tests/security -v

e2e:
	up test run $(E2E_TESTS) --e2e

publish:
	@if [ -z "$(tag)" ]; then echo "Error: tag is not set. Usage: make publish tag=<version>"; exit 1; fi
	up project build --push --tag $(tag)
