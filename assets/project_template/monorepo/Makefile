# Tasks of this monorepo. `make help` lists them; `make` runs generate, format, analyze and test.
# Apps live in apps/<folder>, packages in packages/<folder>; the scripts find them themselves.
SHELL := /bin/bash -e -o pipefail
.DEFAULT_GOAL := all

# The app that `make run` and `make build-*` work on: `make run APP=desktop`. By default the first
# folder in apps/ with a lib/main.dart.
APP ?= $(patsubst apps/%/lib/main.dart,%,$(firstword $(wildcard apps/*/lib/main.dart)))

# The environment to run and build for. config/$(ENV).json goes to --dart-define-from-file when it
# exists: `make run ENV=production`, `make build-apk ENV=production`. The path is relative to the
# app, because the recipes run in apps/$(APP).
ENV ?= development
DEFINES := $(if $(wildcard config/$(ENV).json),--dart-define-from-file=../../config/$(ENV).json,)

# The Sentry DSN (docs/rules/configuration.md): config/sentry.local.json of the root, git-ignored,
# when it exists. Without it the apps keep their log and send nothing.
SENTRY := $(if $(wildcard config/sentry.local.json),--dart-define-from-file=../../config/sentry.local.json,)

# Release builds are obfuscated; the symbols to read their stack traces go here. Keep this folder
# for every release and upload it to the crash reporter (docs/rules/security.md, "Obfuscation").
DEBUG_INFO_DIR := build/debug-info
RELEASE := --release --obfuscate --split-debug-info=$(DEBUG_INFO_DIR) $(DEFINES) $(SENTRY)

.PHONY: all
all: generate format analyze test ## Generate, format, analyze and test

.PHONY: ci
ci: ## What CI runs: locked dependencies, generated code, analyze, test
	@flutter pub get --enforce-lockfile
	@bash scripts/generate.bash
	@bash scripts/analyze.bash
	@bash scripts/test.bash

.PHONY: precommit
precommit: all ## Check the branch before a commit

.PHONY: help
help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: get
get: ## Get the dependencies of every member (also generates the localizations)
	@flutter pub get

.PHONY: upgrade
upgrade: ## Upgrade the dependencies within their constraints
	@flutter pub upgrade

.PHONY: outdated
outdated: get ## List outdated dependencies
	@flutter pub outdated --show-all --dev-dependencies --transitive

.PHONY: generate
generate: ## Generate code (l10n, freezed, drift, json) in every member and format it
	@bash scripts/generate.bash

.PHONY: watch
watch: get ## Regenerate code on every change
	@dart run build_runner watch --workspace --delete-conflicting-outputs

.PHONY: format
format: ## Format the code of every member
	@bash scripts/format.bash

.PHONY: fix
fix: ## Apply the analyzer's fixes, then format
	@dart fix --apply
	@bash scripts/format.bash

.PHONY: analyze
analyze: get ## Analyze every member
	@bash scripts/analyze.bash

.PHONY: test
test: get ## Run the tests of every member
	@bash scripts/test.bash

.PHONY: run
run: get ## Run an app (APP=<folder>, ENV=development by default)
	@cd apps/$(APP) && flutter run $(DEFINES) $(SENTRY)

.PHONY: build-apk
build-apk: generate ## Build a release APK of APP
	@cd apps/$(APP) && flutter build apk $(RELEASE)

.PHONY: build-appbundle
build-appbundle: generate ## Build a release Android App Bundle of APP
	@cd apps/$(APP) && flutter build appbundle $(RELEASE)

.PHONY: build-ipa
build-ipa: generate ## Build a release iOS archive and IPA of APP
	@cd apps/$(APP) && flutter build ipa $(RELEASE)

.PHONY: build-macos
build-macos: generate ## Build a release macOS app of APP
	@cd apps/$(APP) && flutter build macos $(RELEASE)

.PHONY: build-windows
build-windows: generate ## Build a release Windows app of APP
	@cd apps/$(APP) && flutter build windows $(RELEASE)

.PHONY: build-linux
build-linux: generate ## Build a release Linux app of APP
	@cd apps/$(APP) && flutter build linux $(RELEASE)

.PHONY: build-web
build-web: generate ## Build a release web app of APP (no --obfuscate on the web: source maps instead)
	@cd apps/$(APP) && flutter build web --release --source-maps $(DEFINES)

.PHONY: doctor
doctor: ## Check the Flutter installation
	@flutter doctor -v

.PHONY: clean
clean: ## Remove build output and coverage of every member
	@for member in apps/*/ packages/*/; do \
		[ -f "$$member/pubspec.yaml" ] && (cd "$$member" && flutter clean && rm -rf coverage reports); \
	done; true
