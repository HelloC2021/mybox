# KC2/K10Plus 设备树 4.19 移植指南

目标: 把 KC2 实机设备树(4.4)移植到 RKR12/TinkerBoard2 的 4.19 内核,
产出 `rk3399-kc2.dtb`, 放入 resource.img 后即可在 KC2 上启动 Android 11。

## 素材（本目录及仓库）

| 文件 | 说明 |
|---|---|
| `reference/kc2_fdt.dtb` | KC2 实机导出的原始 fdt (Android 7.1, 86KB) |
| `reference/kc2_stock_fdt.dts` | 上者反编译 (4405 行, 黄金参考) |
| `reference/tinker-4.19/rk3399-tinker-board-2.dts/.dtsi` | Tinker Board 2 的 4.19 参考板级文件 (231+2281 行) |
| `dts/kc2_override.dts` | IR 码表覆盖块 (含海格森3528 合并表, 直接可用) |
| `../patches/remotectl_mouse_4.19.patch` | 鼠标模式驱动补丁 (build.sh 自动应用) |

## 硬件画像（来自实机 fdt，已核实）

- **形态: HDMI 盒子** — DSI(`dsi@ff968000`)/eDP/GT9xx 触摸全部 `disabled`，HDMI `okay`
- PMIC: RK808
- WiFi: SDIO0 + `wifi_chip_type = "ap6354"`（历史标签，芯片实际为 AP6356S 一类，
  固件选 AP6356S 三件套 + nvram，与 ROCK960 同款处理）
- 蓝牙: UART0 (`wireless-bluetooth`)
- IR: `pwm@ff420030`, `remote_pwm_id=3`, `handle_cpu_id=1`, `remote_support_psci=1`
- 存储: eMMC (sdhci `fe330000`, HS400) + SD 卡
- 加速度/霍尔/耳机检测等节点存在但多为 disabled

## 移植步骤

1. 以 `reference/tinker-4.19/rk3399-tinker-board-2.dts` 为骨架,
   复制为 `rk3399-kc2.dts`（Tinker 的 dtsi 依赖保持 include 不变）
2. 从 `kc2_stock_fdt.dts` 迁移 KC2 特有节点（对照反编译源）:
   - `pwm@ff420030` IR 节点 + 码表（或直接把 `dts/kc2_override.dts` 的合并表合入）
   - `wireless-wlan`/`sdio-pwrseq`/`wireless-bluetooth` 节点与 pinctrl
   - UART2 console、eMMC/SD、HDMI 使能
3. **4.4 → 4.19 绑定差异重点核对**（Tinker dts 同款外设可对照抄写）:
   - USB3: 4.4 的 `usbdrd3_0` 组合节点写法与 4.19 不同（dwc3 拆分 + phy 节点）
   - GPU Mali-T860: 4.19 用 `rockchip,rk3399-mali` + opp 表
   - VOP/显示路由: `display-subsystem` + `route_hdmi` 结构
   - RK808 regulator: 名字基本一致, 核对 `vcc_ddr`/`vcc1v8` 等实际走线
4. 内核 config 用 `tinker_board_2_defconfig`（`build.sh kernel` 自动）
5. 编译产物: `rk3399-kc2.dtb` → 打包进 resource.img → 只刷 resource 分区
   （bootloader/DDR 不动, 风险最低）

## 风险与注意

- **AVB**: RKR12 固件启用 AVB。若刷修改后的 resource 后校验失败,
  需同时刷禁用校验的 vbmeta (`--disable-verity --disable-verification`) 或关闭 AVB 开关
- 首次点亮务必接 **UART 串口 (1500000)** 观察启动日志
- 显示先以 HDMI 为准; 若 KC2 还有别的显示接口(实机 fdt 显示无), 以实测为准
- 海格森3528 码表已合并在 `ir_key1` (24 项, MAX_NUM_KEYS=60 足够),
  驱动按"第一个匹配 usercode 表"查找, 勿并列两个 0xfe01 表
