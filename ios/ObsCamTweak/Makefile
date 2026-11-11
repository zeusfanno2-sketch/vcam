TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Camera SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ObsCamTweak

ObsCamTweak_FILES = Tweak.xm
ObsCamTweak_FRAMEWORKS = Foundation UIKit AVFoundation CoreMedia CoreVideo
ObsCamTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
