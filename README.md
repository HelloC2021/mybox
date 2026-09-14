# mybox — KC2 / K10Plus (RK3399) Android 11 适配

基于 [TinkerBoard2-Android](https://github.com/TinkerBoard2-Android)（华硕公开的 RK3399 Android 11，
内核 4.19.172，含 `drivers/input/remotectl`）。

## 目标

1. KC2 / K10Plus 设备树移植（dts bring-up）
2. **海格森3528 遥控器**完整适配：12 键码表 + 驱动级鼠标模式（方向=光标 / OK=中键 / 返回=右键，鼠标键切换）
3. GitHub Actions 自动编译：内核 + dtb + boot 镜像

## 流水线

- `kernel.yml` — push 自动触发 / 手动 dispatch（可指定 defconfig 与 make 目标）。
  源码在 runner 上直接从 GitHub 克隆（github-to-github，快），产出 `Image(.gz)/dtb` 挂 Artifacts。

## 目录

```
.github/workflows/kernel.yml   # 内核构建流水线
patches/remotectl_mouse_4.19.patch  # remotectl 鼠标模式补丁（预留 keycode 0x1000~0x10ff）
dts/kc2_haigesen3528_ir.dtsi   # 海格森3528 12键码表（usercode 0xfe01）
```

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

原理与键值由来见主项目 `ADAPTATION_NOTES.md`（驱动解码窗口错位 1 位 → usercode 0xFE01，与原装遥控器共用表）。

## 待办

- [ ] KC2 实机 dts 导出（/sys/firmware/fdt）→ 4.19 dts 移植
- [ ] 全量 ROM 构建（需 x86 自托管 runner）
- [ ] 镜像工作流：外网仓库 → 本仓库孤儿分支/Release 存档
