# Tasks of this project. `make help` lists them; `make` runs generate, format, analyze and test.
SHELL := /bin/bash -e -o pipefail
.DEFAULT_GOAL := all

# The environment to run and build for. config/$(ENV).json goes to --dart-define-from-file when it
# exists: `make run ENV=production`, `make build-apk ENV=production`.
ENV ?= development
DEFINES := $(if $(wildcard config/$(ENV).json),--dart-define-from-file=config/$(ENV).json,)

# Release builds are obfuscated; the symbols to read their stack traces go here. Keep this folder
# for every release and upload it to the crash reporter (docs/rules/security.md, "Obfuscation").
DEBUG_INFO_DIR := build/debug-info
RELEASE := --release --obfuscate --split-debug-info=$(DEBUG_INFO_DIR) $(DEFINES)

.PHONY: all
all: generate format analyze test ## Generate, format, analyze and test

.PHONY: ci
ci: ## What CI runs: locked dependencies, format check, generated code, analyze, test
	@flutter pub get --enforce-lockfile
	@dart format --output=none --set-exit-if-changed lib test
	@dart run build_runner build --delete-conflicting-outputs
	@flutter analyze --no-pub
	@flutter test --no-pub --coverage

.PHONY: precommit
precommit: all ## Check the branch before a commit

.PHONY: help
help: ## List the targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: get
get: ## Get the dependencies (also generates the localizations)
	@flutter pub get

.PHONY: upgrade
upgrade: ## Upgrade the dependencies within their constraints
	@flutter pub upgrade

.PHONY: outdated
outdated: get ## List outdated dependencies
	@flutter pub outdated --show-all --dev-dependencies --transitive

.PHONY: generate
generate: get ## Generate code (freezed, drift, json) and format it
	@dart run build_runner build --delete-conflicting-outputs
	@dart format lib test

.PHONY: watch
watch: get ## Regenerate code on every change
	@dart run build_runner watch --delete-conflicting-outputs

.PHONY: l10n
l10n: ## Generate the localizations from the .arb files
	@flutter gen-l10n

.PHONY: format
format: ## Format the code
	@dart format lib test

.PHONY: fix
fix: ## Apply the analyzer's fixes, then format
	@dart fix --apply
	@dart format lib test

.PHONY: analyze
analyze: get ## Check formatting and analyze
	@dart format --output=none --set-exit-if-changed lib test
	@flutter analyze --no-pub

.PHONY: test
test: get ## Run the tests with coverage
	@flutter test --no-pub --coverage

.PHONY: run
run: get ## Run the app (ENV=development by default)
	@flutter run $(DEFINES)

.PHONY: build-apk
build-apk: generate ## Build a release APK
	@flutter build apk $(RELEASE)

.PHONY: build-appbundle
build-appbundle: generate ## Build a release Android App Bundle
	@flutter build appbundle $(RELEASE)

.PHONY: build-ipa
build-ipa: generate ## Build a release iOS archive and IPA
	@flutter build ipa $(RELEASE)

.PHONY: build-macos
build-macos: generate ## Build a release macOS app
	@flutter build macos $(RELEASE)

.PHONY: build-windows
build-windows: generate ## Build a release Windows app
	@flutter build windows $(RELEASE)

.PHONY: build-linux
build-linux: generate ## Build a release Linux app
	@flutter build linux $(RELEASE)

.PHONY: build-web
build-web: generate ## Build a release web app (no --obfuscate on the web: source maps instead)
	@flutter build web --release --source-maps $(DEFINES)

.PHONY: doctor
doctor: ## Check the Flutter installation
	@flutter doctor -v

.PHONY: clean
clean: ## Remove build output, coverage and generated tool files
	@flutter clean
	@rm -rf coverage
