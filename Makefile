SCHEME := Glucose
CONFIG := Debug
DERIVED := build
APP := $(DERIVED)/Build/Products/$(CONFIG)/Glucose.app

.PHONY: run build kill clean

# Kill the running app, rebuild, and launch the fresh build.
run: build kill
	@open $(APP)

build:
	@xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) build

# Quit the running instance (it's a menu-bar app, so there's no window to close).
kill:
	@killall Glucose 2>/dev/null || true

clean:
	@rm -rf $(DERIVED)
	@xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) clean >/dev/null 2>&1 || true
