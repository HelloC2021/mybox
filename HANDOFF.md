# KC2/K10Plus RK3399 海格森3528 遥控适配 + Android TV ROM 构建项目

## 设备信息

- 板卡: KC2 / K10Plus（RK3399，HDMI 盒子形态，无面板/触摸）
- 固件: Android 7.1.2，内核 4.4.126，远程调试 ADB: 192.168.198.26:5555
- 编译机: 192.168.199.125（ubuntu/ubuntu，x86_64，10核/28GB/512G 工作区）
- 红外遥控: **海格森3528**（NEC 协议，地址 0x01，驱动解码后用户码 0xFE01）
- CNB 仓库: https://cnb.cool/xiaoqi-cool/rk3399_androidTV（token: agent-token）
- GitHub 镜像: https://github.com/HelloC2021/mybox（token: agent-token）

## 已完成的关键工作

### 1. 海格森3528 红外遥控破解（✅ 全部完成）

- 驱动 `rockchip_pwm_remotectl`（RK PWM IR）解码窗口错位 1 位
- 实际 NEC 地址 0x01 被驱动解码为用户码 **0xFE01**（与原装遥控器 A 相同）
- 驱动键值 = ((~NEC_data) >> 1) | 0x80
- 12 键全部实测确认：

| 按键 | scancode | 按键模式 keycode | 鼠标模式 |
|---|---|---|---|
| 电源 | 0xBF | 116 POWER | 116 |
| 菜单 | 0xB3 | 139 MENU | 139 |
| 返回 | 0xE6 | 158 BACK | 158 |
| 确认(OK) | 0xEC | 232 REPLY | 中键 |
| 上 | 0xE9 | 103 UP | 光标↑ |
| 下 | 0xE5 | 108 DOWN | 光标↓ |
| 左 | 0xAE | 105 LEFT | 光标← |
| 右 | 0xAF | 106 RIGHT | 光标→ |
| HOME | 0xEE | 102 HOME | 102 |
| 音量+ | 0xE7 | 115 | 115 |
| 音量− | 0xEF | 114 | 114 |
| 鼠标键 | 0xFF | 预留 0x10F0 | 模式切换 |

- **热补丁已生效**（`apply_table.sh` 内存写入，重启动态生效），海格森3528 全部按键已在 KC2 上实测可用

### 2. 热补丁脚本（✅ 已部署到 125：/mnt/data/mybox/build_rom.sh 同目录）

- `apply_table.sh`：定位 `remotectl_button` 内核符号 → /dev/mem 追踪指针 → 校验原表 → 写入 24 项合并码表（原装A 12键 + 海格森3528 12键）
- 安全校验三重：指针特征 / 原表内容 / 回读验证
- 重启后需重跑（RAM 状态不持久）

### 3. Firefly A10 SDK（✅ 已下载解压到 125：/mnt/data/ff-a10sdk/rk3399_Android10.0/）

- 来源: Firefly 下载页 community.t-firefly.com/en/doc/download/85 → "Android10.0 SDK"
- 完整 Android 10 源码 + 工具链，单仓库结构
- **内核 4.19.193**，remotectl 驱动在位
- **基线编译成功**: Image 29MB + 全套 dtbs
- 自带 linaro 6.3.1 交叉工具链: `prebuilts/gcc/linux-x86/aarch64/gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu/bin/`
- 自带 `rk3399_atv` 产品（Android TV），但 ATK 桌面用 FongMi-TV 替代
- 设备树参考: `kernel/arch/arm64/boot/dts/rockchip/rk3399-evb-ind-lpddr4-v13-android-avb.dts` + `rk3399-evb-ind.dtsi`
- 注意: 树里 `rk3399-evb-ind-lpddr4-v11.dtb` 和 `v11-avb.dtb` 编译会失败（px30 引用缺失），只编指定 dtb 即可

### 4. CNB 仓库（✅ 已推送构建编排 + 补丁 + 码表）

- 仓库: cnb.cool/xiaoqi-cool/rk3399_androidTV
- Token: cnb:976FjflV8u17135BaLInePzznCP
- 已推送: build.sh, build_rom.sh, .cnb.yml, .cnb/web_trigger.yml, patches/remotectl_mouse_4.19.patch, dts/kc2_override.dts, dts/kc2_haigesen3528_ir.dtsi, device_overlay/, docs/
- Release `apps-v1`: AirDroid + Magisk APK
- CNB 云开发已配置 10 核 ubuntu:20.04

### 5. 鼠标模式补丁（✅ 已生成 remotectl_mouse_4.19.patch）

- 预留 keycode 段 0x1000~0x10ff（DTS 中声明但驱动内部解释，不注册为 EV_KEY）
- 鼠标键切换 → 模式翻转
- 鼠标模式下: 方向键=光标移动(REL_X/Y)、OK=中键(BTN_MIDDLE)、返回保持
- 按键模式下: 方向键=DPAD、OK=KEY_REPLY(232)
- 长按利用 NEC repeat 帧持续步进光标
- **待移植到 Firefly A10 树的 remotectl**（两代驱动结构有差异，Tinker 版补丁不可直接 apply，需按 gen_ff2.py 逻辑重新生成）

## ⏳ 当前进行中 / 待完成

### A11 源码同步（125 机器）

- 脚本: `/mnt/data/mybox/build_rom.sh kernel`
- 状态: 进行中，**已下载 25GB+**（.repo/ 占 217GB，工作目录 ~34GB）
- dockermirror 排队慢，但断点续传可用
- **紧急**: 125 机器 SSH (192.168.199.125) 暂时连不上，需要用户确认机器状态
- 用户也可自行在 125 上查看: `tail -20 /mnt/data/build_tv_rom.log`

### TV 内核编译（等 A11 源码就绪后）

```bash
cd /mnt/data/ff-a10sdk/rk3399_Android10.0
source build/envsetup.sh
lunch rk3399_firefly-userdebug
make ARCH=arm64 CC=aarch64-linux-gnu-gcc-10 rockchip_defconfig
make ARCH=arm64 CC=aarch64-linux-gnu-gcc-10 -j10 Image rockchip/rk3399-kc2.dtb
```

- 已验证: Image 29MB 可成功编译（rockchip_defconfig + linaro 6.3.1 工具链）
- 已验证: rk3399-kc2.dtb 可成功编译（113KB）
- 注意: `make dtbs` 会因 px30-evb dts 引用缺失而失败 → 只编指定 dtb

### remotectl 鼠标模式适配（Firefly A10 树）

- 补丁生成脚本: `gen_ff2.py`（未完成，需要逐行匹配 Firefly 版源码）
- Firefly remotectl 源码: 已拉取为 `remotectl_firefly.c`（719 行，与 Tinker 828 行版本不同代际）
- 需要将鼠标模式逻辑（预留键值段处理、模式切换、光标移动）适配到 Firefly 版源码结构

## 关键文件清单（项目根目录）

| 文件 | 用途 |
|---|---|
| `build_rom.sh` | 125 上全量构建脚本（同步+编译+打包）|
| `patch_table.py` → `apply_table.sh` | 内核码表热补丁 |
| `kc2_patched.dtb` | 修改后的 KC2 设备树（含海格森码表）|
| `remotectl_mouse_4.19.patch` | Tinker 树 remotectl 鼠标补丁 |
| `rk3399-kc2.dts` | KC2 设备树源文件（含海格森 IR 表）|
| `dts/kc2_override.dts` | CNB 仓库里的码表覆盖片段 |
| `decode_ir.py` | 红外 NEC 帧解码器（从 kmsg 波形重建）|
| `ADAPTATION_NOTES.md` | 适配笔记（机制分析/码表/监控命令）|
| `海格森3528遥控适配.md` | 完整适配文档 |
| `build_tv_rom.sh` | CNB 构建脚本（已部署 125）|

## 网络加速

- GitHub: `git config --global url."https://dockermirror.truking.top/https://github.com/".insteadOf "https://github.com/"`
- googlesource: `git config --global url."https://aosp.tuna.tsinghua.edu.cn/".insteadOf "https://android.googlesource.com/"`
- apt: 清华源
- 代理备选: http://192.168.199.67:10808（用户不推荐）

## 注意事项

- 125 机器 /mnt/data 磁盘 541GB，A11 源码 251GB + Firefly SDK 70GB + 产物 ~100GB = 需注意空间
- A11 同步脚本已改 `--fail-fast` 移除（网络不稳定时重跑续传）
- code_print/dbg_level 参数重启后丢失，需重设: `echo 1 > /sys/module/rockchip_pwm_remotectl/parameters/code_print`
- kallsyms 符号地址: `remotectl_button` = 0xffffff8009537028（无 KASLR，固定）
