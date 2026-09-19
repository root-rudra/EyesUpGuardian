.PHONY: app test test-integration install run clean

app:
	swift build -c release --product EyesUpGuardian
	Scripts/bundle.sh release

test:
	swift test

test-integration:
	EYESUP_INTEGRATION=1 swift test

install: app
	rm -rf /Applications/EyesUpGuardian.app
	cp -R build/EyesUpGuardian.app /Applications/

run: app
	open build/EyesUpGuardian.app

clean:
	swift package clean
	rm -rf build
