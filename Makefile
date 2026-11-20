APP := sleepless
SWIFT_FORMAT := swift-format
SWIFT_FORMAT_VERSION := 602.0.0
SWIFT_FORMAT_PATHS := Package.swift Sources
DIST := dist
VERSION ?= dev
.DEFAULT_GOAL := help

.PHONY: help dev build package clean check check-fix install uninstall

help:
	@printf "Commands:\n"
	@printf "  make build      Build debug and release binaries\n"
	@printf "  make package    Build a universal release archive in dist/ (VERSION=v1.2.3)\n"
	@printf "  make check      Check format and lint\n"
	@printf "  make check-fix  Fix format, then check\n"
	@printf "  make clean      Remove Swift build output\n"
	@printf "  make dev        Run the debug app through SwiftPM\n"
	@printf "  make install    Build from source, install and start at login\n"
	@printf "  make uninstall  Stop, remove the login agent and the sudoers rule\n"

build:
	swift build
	swift build -c release

package:
	swift build -c release --arch arm64 --arch x86_64
	rm -rf $(DIST) && mkdir -p $(DIST)/stage
	@# The universal output folder differs between SwiftPM versions, so ask SwiftPM for it.
	cp "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(APP)" $(DIST)/stage/
	printf "%s\n" "$(VERSION)" > $(DIST)/stage/VERSION
	tar -czf $(DIST)/$(APP)-macos-universal.tar.gz -C $(DIST)/stage $(APP) VERSION
	rm -rf $(DIST)/stage
	cd $(DIST) && shasum -a 256 $(APP)-macos-universal.tar.gz > $(APP)-macos-universal.tar.gz.sha256

clean:
	swift package clean
	rm -rf $(DIST)

check:
	@test "$$($(SWIFT_FORMAT) --version)" = "$(SWIFT_FORMAT_VERSION)"
	$(SWIFT_FORMAT) lint --strict --recursive --parallel $(SWIFT_FORMAT_PATHS)

check-fix:
	$(SWIFT_FORMAT) format --in-place --recursive --parallel $(SWIFT_FORMAT_PATHS)
	$(MAKE) check

dev:
	swift run $(APP)

install:
	scripts/install.sh --from-source

uninstall:
	scripts/uninstall.sh
