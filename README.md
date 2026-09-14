# mybox — KC2 / K10Plus (RK3399) Android TV 11 适配

基于 [TinkerBoard2-Android](https://github.com/TinkerBoard2-Android)（华硕公开的 RK3399 Android 11，
内核 4.19.172，含 `drivers/input/remotectl`），参考 [maerdelin/ROCK960-AndroidTV11](https://github.com/maerdelin/ROCK960-AndroidTV11)
的 ATV 产品与板级 dts 生成方法。

## 目标

1. KC2 / K10Plus 设备树移植（4.4 实机 fdt → 4.19，HDMI 盒子形态）
2. **海格森3528 遥控器**完整适配：12 键码表 + 驱动级鼠标模式（方向=光标 / OK=中键 / 返回=右键，鼠标键切换）
3. 预装 AirDroid / Magisk 系统应用，默认开启网络 ADB
4. 编译产出：内核 + dtb（快速迭代）→ 完整 Android TV 11 ROM

## 构建方式

| 方式 | 用途 | 入口 |
|---|---|---|
| **CNB 云原生构建（推荐）** | 全流程，512G 工作区 | `.cnb.yml` + `bash build.sh kernel\|full`，按钮见分支页 |
| GitHub Actions | 内核+dtb 快速验证 | `.github/workflows/kernel.yml`，push 自动 |
| 任意 x86 Linux 本地 | 同 CNB，见指南 | `bash build_rom.sh`（Docker 版）|

详细指南: [docs/local-build.md](docs/local-build.md)（本地）、[docs/kc2-dts-port.md](docs/kc2-dts-port.md)（dts 移植）

## 目录

```
build.sh                        # 一键构建脚本 (CNB/本地通用, 全国内直连)
.cnb.yml                        # CNB 流水线 (push 校验 / 手动构建按钮)
.cnb/web_trigger.yml            # 分支页构建按钮定义
patches/remotectl_mouse_4.19.patch  # remotectl 鼠标模式补丁 (预留 keycode 0x1000~0x10ff)
dts/kc2_override.dts            # KC2 整机覆盖块 (HDMI 盒子 + 24 项合并码表)
dts/kc2_haigesen3528_ir.dtsi    # 海格森3528 码表片段
device_overlay/                 # AirDroid/Magisk 系统应用 + 网络 ADB props
reference/kc2_fdt.dtb           # KC2 实机 fdt (Android 7.1)
reference/kc2_stock_fdt.dts     # 实机 fdt 反编译 (4405 行)
reference/tinker-4.19/          # Tinker Board 2 的 4.19 参考板级文件
docs/                           # dts 移植 / 本地构建 / runner 指南
```

预装 APK 载体: Release [`apps-v1`](https://github.com/HelloC2021/mybox/releases/tag/apps-v1)
(AirDroid 4.3.12 + Magisk v30.7), 构建时自动拉取。

## 海格森3528 键位

| 按键 | scancode | 按键模式 | 鼠标模式 |
|---|---|---|---|
| 电源 | 0xBF | 116 | 116 |
| 菜单 | 0xB3 | 139 | 139 |
| 返回 | 0xE6 | 158 | 158 |
| 确认(OK) | 0xEC | 232 | **中键** |
| 上/下/左/右 | E9/E5/AE/AF | DPAD | **光标移动** |
| HOME | 0xEE | 102 | 102 |
| 音量± | E7/EF | 115/114 | 同 |
| 鼠标键 | 0xFF | — | **模式切换** |

原理与键值由来：驱动解码窗口错位 1 位 → usercode 0xFE01，与原装遥控器 A 共用表
（键值集合不相交），DTS 中合并为一张 24 项表。

## 进度

- [x] KC2 实机 fdt 导出 + 反编译（reference/）
- [x] 4.19 移植素材与指南（reference/tinker-4.19 + docs/kc2-dts-port.md）
- [x] 海格森3528 码表 + 鼠标补丁 + ROM 定制层入库
- [x] CNB 云构建流水线（512G 工作区，无需代理）
- [ ] **rk3399-kc2.dts 移植本体**（按 docs/kc2-dts-port.md 执行）
- [ ] CNB 首跑验证（kernel 阶段 → full 阶段）
- [ ] 刷机实测海格森3528（按键 + 鼠标模式 + Magisk root + 网络 ADB）
- [ ] （长期）向 KickPI/瑞芯微申请 RKR12 RK3399 官方源码授权
