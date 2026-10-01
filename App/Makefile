ARCHS = arm64
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = ICamController
ICamController_FILES = main.m ICAppDelegate.m ICMainController.m ../Core/ICPaths.m ../Core/ICSettings.m ../Core/ICRender.m ../Core/ICMediaSource.m ../Core/ICFrameEngine.m ../UI/ICAdjustments.m
ICamController_CFLAGS = -fobjc-arc -I../Core -I../UI
ICamController_FRAMEWORKS = UIKit Foundation PhotosUI Photos UniformTypeIdentifiers AVFoundation CoreMedia CoreVideo CoreImage ImageIO QuartzCore
ICamController_RESOURCE_FILES = Info.plist
ICamController_RESOURCE_DIRS = Resources
ICamController_CODESIGN_FLAGS = -SEntitlements.plist
ICamController_INSTALL_PATH = /Applications
include $(THEOS_MAKE_PATH)/application.mk
