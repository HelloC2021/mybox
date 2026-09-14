# KC2/K10Plus ROM 定制层
# 用法: 全量 ROM 构建(device/asus/tinker_board_2 树)中
#   1) 将本目录拷贝为 device/kc2/
#   2) 在 device/asus/tinker_board_2/tinker_board_2.mk 末尾追加:
#        $(call inherit-product, device/kc2/kc2_rom.mk)

PRODUCT_PACKAGES += \
    AirDroid \
    Magisk

# ---- 网络ADB默认开启 ----
PRODUCT_SYSTEM_PROPERTIES += \
    persist.adb.tcp.port=5555

# ---- 免鉴权 adb (配合 userdebug) ----
PRODUCT_SYSTEM_PROPERTIES += \
    ro.adb.secure=0

# ---- root 说明 ----
# 1) userdebug 变体: `adb root && adb shell` 即 root (ro.debuggable=1)
# 2) 应用级 root (AirDroid 等请求 su): 需要 Magisk 写入 boot 镜像,
#    计划在 CI 的 build 后处理中用 magiskboot 自动 patch boot.img
#    (KEEPVERITY KEEPFORCEENCRYPT), 见 TODO
