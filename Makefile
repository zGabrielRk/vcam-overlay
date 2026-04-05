export THEOS_DEVICE_IP ?= 127.0.0.1
export THEOS_DEVICE_PORT ?= 22

ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = vcamoverlay
vcamoverlay_FILES = Tweak.xm
vcamoverlay_FRAMEWORKS = UIKit AVFoundation
vcamoverlay_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/tweak.mk

# Empacotar junto com o vcamrootless original
after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)/var/jb/Library/MobileSubstrate/DynamicLibraries/"
	cp "$(THEOS_PROJECT_DIR)/vendor/vcamrootless.dylib" \
	   "$(THEOS_STAGING_DIR)/var/jb/Library/MobileSubstrate/DynamicLibraries/vcamrootless.dylib"
	cp "$(THEOS_PROJECT_DIR)/vendor/vcamrootless.plist" \
	   "$(THEOS_STAGING_DIR)/var/jb/Library/MobileSubstrate/DynamicLibraries/vcamrootless.plist"
