PROJECT := SpotMenu.xcodeproj
SCHEME := SpotMenu
CONFIGURATION ?= Debug
DERIVED_DATA ?= $(CURDIR)/.derivedData
ARCH ?= $(shell uname -m)
DESTINATION ?= platform=macOS,arch=$(ARCH)

XCODEBUILD_BASE = xcodebuild \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" \
	-derivedDataPath "$(DERIVED_DATA)" \
	-destination '$(DESTINATION)'

APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/SpotMenu.app

.PHONY: build test run clean

build:
	$(XCODEBUILD_BASE) build

test:
	$(XCODEBUILD_BASE) test

run: build
	open "$(APP_PATH)"

clean:
	rm -rf "$(DERIVED_DATA)"
