# 26Safari - builds for rootful, rootless AND roothide jailbreaks
#
#   make package                      rootless  (default: Dopamine, palera1n rootless)
#   make package SCHEME=rootful       rootful   (palera1n rootful, checkra1n, unc0ver, Taurine ...)
#   make package SCHEME=roothide      roothide  (needs the roothide fork of Theos, see below)
#   make package-all                  all three in one go, .debs end up in ./packages
#
# Add FINALPACKAGE=1 for a release build:  make package FINALPACKAGE=1
#
# roothide needs roothide's fork of Theos (upstream Theos does not know that scheme):
#   git clone --recursive https://github.com/roothide/theos.git ~/theos-roothide
#   THEOS=~/theos-roothide make package SCHEME=roothide
# This tweak never touches the filesystem, so it does not need libroothide at runtime.

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = MobileSafari

SCHEME ?= rootless

ifeq ($(SCHEME),rootless)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(SCHEME),roothide)
THEOS_PACKAGE_SCHEME = roothide
else ifeq ($(SCHEME),rootful)
# leave THEOS_PACKAGE_SCHEME unset: that is Theos' rootful layout
else
$(error SCHEME must be rootful, rootless or roothide (you gave "$(SCHEME)"))
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = 26safari
26safari_FILES = Tweak.xm
26safari_CFLAGS = -fobjc-arc
26safari_FRAMEWORKS = UIKit QuartzCore CoreImage

include $(THEOS_MAKE_PATH)/tweak.mk

# build every flavour, one after the other (the object files are cleaned in between, so the schemes never mix)
.PHONY: package-all
package-all:
	$(MAKE) clean package SCHEME=rootful  FINALPACKAGE=1
	$(MAKE) clean package SCHEME=rootless FINALPACKAGE=1
	-$(MAKE) clean package SCHEME=roothide FINALPACKAGE=1
	@echo "Done. Look in ./packages (the roothide one is skipped if you are not on the roothide fork of Theos)."
