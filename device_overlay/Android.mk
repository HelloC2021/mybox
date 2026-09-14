LOCAL_PATH := $(call my-dir)

############################
# AirDroid  — /system/app/AirDroid
# 远程管理应用, PRESIGNED 保留原签名
############################
include $(CLEAR_VARS)
LOCAL_MODULE := AirDroid
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := apps/AirDroid_4.3.12.0_airdroidhp.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_MODULE_PATH := $(TARGET_OUT_APPS)
include $(BUILD_PREBUILT)

############################
# Magisk manager — /system/priv-app/Magisk
# 注意: 仅预装 Magisk 管理器不等于 root;
# 真正 root 需要_magisk_写入 boot 镜像(构建后处理)或使用 userdebug 的 adb root。
############################
include $(CLEAR_VARS)
LOCAL_MODULE := Magisk
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := apps/Magisk-v30.7.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_PRIVILEGED_MODULE := true
include $(BUILD_PREBUILT)
