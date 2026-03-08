PROJECT := SpotMenu.xcodeproj
SCHEME := SpotMenu
CONFIGURATION ?= Debug
DERIVED_DATA ?= $(CURDIR)/.derivedData
ARCH ?= $(shell uname -m)
DESTINATION ?= platform=macOS,arch=$(ARCH)
LOCAL_BUILD_ROOT := $(CURDIR)/.codex-build/local-install
LOCAL_DERIVED_DATA := $(LOCAL_BUILD_ROOT)/deriveddata
INSTALL_APP_PATH := /Applications/SpotMenu.app
LOCAL_CODESIGN_IDENTITY ?= SpotMenu

XCODEBUILD_BASE = xcodebuild \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" \
	-derivedDataPath "$(DERIVED_DATA)" \
	-destination '$(DESTINATION)'

APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/SpotMenu.app

.PHONY: build test run clean install-local local sparkle-release

build:
	$(XCODEBUILD_BASE) build

test:
	$(XCODEBUILD_BASE) test

run: build
	open "$(APP_PATH)"

install-local:
	./scripts/install_local_app.sh

local: install-local

sparkle-release:
	./scripts/build_sparkle_release.sh

clean:
	rm -rf "$(DERIVED_DATA)"
