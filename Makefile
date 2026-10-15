TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = MobileSafari

# rootless (Dopamine / palera1n rootless). For rootful palera1n, comment this line out.
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 26safari
26safari_FILES = Tweak.xm
26safari_CFLAGS = -fobjc-arc
26safari_FRAMEWORKS = UIKit QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
