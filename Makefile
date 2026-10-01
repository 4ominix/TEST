export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:15.0
export GO_EASY_ON_ME = 1
include $(THEOS)/makefiles/common.mk
SUBPROJECTS = App Camera Controls
include $(THEOS_MAKE_PATH)/aggregate.mk
