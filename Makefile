TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Zalo

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZaloXposediOS

ZaloXposediOS_FILES = Tweak.m ZXConfig.m ZXLog.m ZXHookEngine.m ZXAntiRecall.m ZXNetwork.m ZXScanner.m ZXUI.m ZXRecallMarker.m ZXBubble.m ZXBubbleIcon.m
ZaloXposediOS_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ZaloXposediOS_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
