APP := mac-sleepless
SWIFT_FORMAT := swift-format
SWIFT_FORMAT_VERSION := 602.0.0
SWIFT_FORMAT_PATHS := Package.swift Sources
.DEFAULT_GOAL := help

.PHONY: help dev build clean check check-fix install uninstall

help:
	@printf "Commands:\n"
	@printf "  make build      Build debug and release binaries\n"
	@printf "  make check      Check format and lint\n"
	@printf "  make check-fix  Fix format, then check\n"
	@printf "  make clean      Remove Swift build output\n"
	@printf "  make dev        Run the debug app through SwiftPM\n"
	@printf "  make install    Build, install and start at login\n"
	@printf "  make uninstall  Stop, remove the login agent and the sudoers rule\n"

build:
	swift build
	swift build -c release

clean:
	swift package clean

check:
	@test "$$($(SWIFT_FORMAT) --version)" = "$(SWIFT_FORMAT_VERSION)"
	$(SWIFT_FORMAT) lint --strict --recursive --parallel $(SWIFT_FORMAT_PATHS)

check-fix:
	$(SWIFT_FORMAT) format --in-place --recursive --parallel $(SWIFT_FORMAT_PATHS)
	$(MAKE) check

dev:
	swift run $(APP)

install:
	scripts/install-startup.sh

uninstall:
	scripts/uninstall-startup.sh
