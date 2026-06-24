TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Sidecar ContinuityDisplay
THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = sidecar-touch-tweak

sidecar-touch-tweak_FILES = Tweak.x
sidecar-touch-tweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
