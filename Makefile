# Developer entry points. `make help` lists them.
SHELL := /bin/bash
.DEFAULT_GOAL := help

# xcodebuild exposes one auto-generated scheme per package, named after it.
SCHEME := onetimesecret-ios
ARCHIVE_NAME := OnetimeSecret
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

.PHONY: help setup build test test-live test-ios lint format docs docs-preview clean check release-prepare release-tag

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

setup: ## One-time machine setup: Homebrew tools and git hooks
	@command -v brew >/dev/null || { echo "Homebrew is required: https://brew.sh"; exit 1; }
	brew bundle --no-upgrade
	pre-commit install --install-hooks
	@echo "Done. Try: make test"

build: ## Build the package (debug)
	swift build

test: ## Run unit tests
	swift test --parallel

test-live: ## Run end-to-end tests against the hosted service (guest unless ONETIME_CUSTOMER_EXTID and ONETIME_API_TOKEN are set)
	ONETIME_LIVE=1 swift test --filter Live

test-ios: ## Run tests on an iOS simulator (IOS_DESTINATION overrides the device)
	set -o pipefail; xcodebuild test -scheme $(SCHEME) -destination "$(IOS_DESTINATION)" \
		-skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO | xcbeautify

lint: ## SwiftFormat (check) + SwiftLint (strict), exactly as CI runs them
	swiftformat --lint --strict .
	swiftlint lint --strict --quiet

format: ## Rewrite sources with SwiftFormat and SwiftLint autocorrect
	swiftformat .
	swiftlint lint --fix --quiet

docs: ## Build the DocC archive into .docc-build
	set -o pipefail; xcodebuild docbuild -scheme $(SCHEME) -destination "generic/platform=macOS" \
		-derivedDataPath .docc-build OTHER_DOCC_FLAGS="--warnings-as-errors" | xcbeautify
	@echo "Archive: $$(find .docc-build -name '$(ARCHIVE_NAME).doccarchive' -type d | head -n 1)"

docs-preview: docs ## Serve the documentation locally on http://localhost:8000
	@ARCHIVE="$$(find .docc-build -name '$(ARCHIVE_NAME).doccarchive' -type d | head -n 1)"; \
	"$$(xcrun --find docc)" process-archive transform-for-static-hosting "$$ARCHIVE" --output-path .docc-build/site; \
	echo "Open http://localhost:8000/documentation/onetimesecret/"; \
	python3 -m http.server --directory .docc-build/site 8000

check: lint test ## Everything a PR needs to pass locally

clean: ## Remove build products
	rm -rf .build .docc-build .swiftpm *.xcresult

release-prepare: ## Bump version + changelog on a release branch: make release-prepare VERSION=1.2.0
	@test -n "$(VERSION)" || { echo "VERSION is required"; exit 2; }
	scripts/release.sh prepare $(VERSION)

release-tag: ## Tag main after the release PR merged: make release-tag VERSION=1.2.0
	@test -n "$(VERSION)" || { echo "VERSION is required"; exit 2; }
	scripts/release.sh tag $(VERSION)
