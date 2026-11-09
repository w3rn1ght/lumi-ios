TARGET := iphone:clang:12.4:12.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Lumi

Lumi_FILES = $(wildcard Sources/*.m)
Lumi_FRAMEWORKS = UIKit WebKit Foundation
Lumi_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations
Lumi_INSTALL_PATH = /Applications
Lumi_RESOURCE_DIRS = Resources
Lumi_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk

# Compile the launch storyboard on macOS (Xcode is required for Theos anyway).
before-Lumi-all:: Resources/LaunchScreen.storyboardc

Resources/LaunchScreen.storyboardc: Support/LaunchScreen.storyboard
	@mkdir -p Resources
	xcrun ibtool --compile "$@" "$<"
