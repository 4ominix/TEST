include $(THEOS)/makefiles/common.mk
TWEAK_NAME = ICamCamera
ICamCamera_FILES = CameraHooks.mm ../Core/ICPaths.m ../Core/ICSettings.m ../Core/ICRender.m ../Core/ICMediaSource.m ../Core/ICFrameEngine.m ../Core/ICSample.m
ICamCamera_CFLAGS = -fobjc-arc -I../Core
ICamCamera_FRAMEWORKS = Foundation AVFoundation CoreMedia CoreVideo CoreImage ImageIO QuartzCore
ICamCamera_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
