.PHONY: app test test-integration perf perf-stats release install run clean icon

# Load Swift Testing's macro plugin explicitly. With only the Command Line Tools installed, SwiftPM's
# build system intermittently omits it on incremental builds ("plugin for module 'TestingMacros' not found").
TESTING_MACROS := $(shell dirname "$$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib
SWIFT_TEST := swift test -Xswiftc -load-plugin-library -Xswiftc "$(TESTING_MACROS)"

app:
	swift build -c release --product EyesUpGuardian
	Scripts/bundle.sh release

test:
	$(SWIFT_TEST)

test-integration:
	EYESUP_INTEGRATION=1 $(SWIFT_TEST)

perf: app
	Scripts/perf.sh

install: app
	rm -rf /Applications/EyesUpGuardian.app
	cp -R build/EyesUpGuardian.app /Applications/

run: app
	open build/EyesUpGuardian.app

clean:
	swift package clean
	rm -rf build

icon:
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Sources/EyesUpApp/Resources/AppIcon.icns
	@echo "Wrote Sources/EyesUpApp/Resources/AppIcon.icns"

release:
	Scripts/release.sh

perf-stats:
	@echo "Measuring with the stats readout and HUD on (visible-surface budget, 1.5%)"
	Scripts/perf-stats.sh
