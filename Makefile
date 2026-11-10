TARGET := iphone:clang:12.4:12.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = Lumi

Lumi_FILES := $(wildcard Sources/*.m) \
              $(wildcard Vendor/libwebp/src/dec/*.c) \
              $(wildcard Vendor/libwebp/src/dsp/*.c) \
              $(wildcard Vendor/libwebp/src/utils/*.c)
Lumi_CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
               -Wno-unused-function -Wno-sign-compare -Wno-unknown-warning-option
Lumi_CFLAGS += -Wno-unused-variable -Wno-missing-braces -Wno-unused-but-set-variable \
               -Wno-constant-logical-operand -Wno-unused-local-typedef -Wno-gnu-folding-constant \
               -Wno-tautological-constant-out-of-range-compare -Wno-format-nonliteral
Lumi_CFLAGS += -I$(THEOS_PROJECT_DIR)/Vendor/libwebp
Lumi_FRAMEWORKS := UIKit Foundation SafariServices WebKit
# libwebp decoder (chromium fork, BSD-3) is vendored under Vendor/libwebp.
Lumi_CCFLAGS := -I$(THEOS_PROJECT_DIR)/Vendor/libwebp -Wno-unused-function
Lumi_CCFLAGS += -Wno-sign-compare -Wno-missing-braces -Wno-unused-variable
# The ARM NEON paths are hand written and need the unaligned-access assumption.
Lumi_CCFLAGS += -fno-strict-aliasing
Lumi_INSTALL_PATH = /Applications
Lumi_RESOURCE_DIRS = Resources
Lumi_CODESIGN_FLAGS = -S

include $(THEOS_MAKE_PATH)/application.mk
