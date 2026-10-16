TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = MobileSafari

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 26safari
26safari_FILES = Tweak.xm
26safari_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
