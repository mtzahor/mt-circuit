APP := build/MT Circuit.app
# With only the Command Line Tools installed, SwiftPM loads the Swift Testing macros through an
# out-of-process plugin server, which can fail intermittently; loading them in-process is reliable.
TESTING_PLUGINS := $(shell xcode-select -p)/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(wildcard $(TESTING_PLUGINS)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: all app debug run test clean icon package

all: app

app:
	scripts/build-app.sh release

debug:
	scripts/build-app.sh debug

package:
	scripts/package.sh

run: app
	open "$(APP)"

test:
	swift test $(TEST_FLAGS)

icon:
	scripts/make-icon.sh

clean:
	swift package clean
	rm -rf build
