# device_overlay — KC2/K10Plus ROM 定制层

全量 ROM 构建时合入 TinkerBoard2-Android 设备树:

| 文件 | 作用 |
|---|---|
| `apps/` | 预装 APK (AirDroid 77MB / Magisk 11MB) |
| `Android.mk` | AirDroid → `/system/app`、Magisk → `/system/priv-app` (PRESIGNED) |
| `kc2_rom.mk` | PRODUCT_PACKAGES + 网络ADB默认开启 (persist.adb.tcp.port=5555) + ro.adb.secure=0 |

## 接入方法 (全量 ROM 构建)

```bash
# 在 TinkerBoard2-Android 源码树根目录
cp -r device_overlay device/kc2
echo '$(call inherit-product, device/kc2/kc2_rom.mk)' >> device/asus/tinker_board_2/tinker_board_2.mk
```

## root 权限三层方案

| 层 | 机制 | 状态 |
|---|---|---|
| adb root | userdebug 变体, `adb root` 即 root | ✅ ROM 变体选 userdebug 即得 |
| 网络ADB | `persist.adb.tcp.port=5555` + `ro.adb.secure=0` | ✅ 已配置 |
| 应用级 root (su) | Magisk 写入 boot 镜像 (CI 后处理) | ⏳ TODO: magiskboot patch 步骤 |

注意: 预装 Magisk 管理器只是入口; 完整 root 必须把 magisk init 注入 boot.img
(计划: CI 用 magiskboot 对构建出的 boot.img 做 KEEPVERITY patch 后再打包)。
