# 本地全量构建指南（不依赖 GitHub runner）

适用于任何 x86_64 Linux 机器（Ubuntu 20.04/22.04/Kali 均可，编译在 Docker 内执行）。

## 前置要求

| 项 | 要求 |
|---|---|
| 磁盘 | ≥300GB 空闲（源码 ~200GB + 产物 ~100GB） |
| 内存 | ≥16GB（推荐 28GB+） |
| Docker | 已安装，当前用户在 docker 组 |
| 工具 | git、python3、repo（清华源: `curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo && chmod a+x /usr/local/bin/repo`） |
| 网络 | 需要能访问 github.com 的代理（脚本内置 `192.168.199.67:10808`，按需修改脚本内 `PROXY=`） |

## 使用

```bash
# 1. 克隆本仓库
git clone https://github.com/HelloC2021/mybox.git
cd mybox

# 2. 按需修改 build_rom.sh 顶部的 ROOT/MYBOX/PROXY 路径
# 3. 启动 (kernel 阶段: 同步源码 + 补丁 + 内核/dtb)
./build_rom.sh kernel

# 4. 全量 ROM (完整 Android 11 + AirDroid/Magisk 系统应用 + 网络ADB + boot注入)
./build_rom.sh full
```

## 特性

- **断点续传**：`repo sync` 中断后重跑脚本自动从断点继续（.repo 持久保留）
- **增量构建**：源码树持久化，后续定制只需增量 sync（分钟级）+ 增量编译
- **ccache**：挂载持久化，重复编译内核显著提速
- **代理隔离**：仅 git/repo（GitHub 流量）走代理；apt/repo 工具/Docker 走国内镜像直连
- **产物**：`/mnt/data/out/`（Image、rk3399-kc2.dtb）+ full 阶段的 `out/target/product/tinker_board_2/`（含 Magisk 注入后的 boot.img）

## 脚本做了什么（6 步）

1. 同步 mybox（补丁/码表/定制层来源）
2. `repo init + repo sync`（TinkerBoard2-Android，744 仓库，REPO_URL 指向清华镜像绕过被墙的 gerrit.googlesource.com）
3. 合入定制层（device/kc2：AirDroid/Magisk 系统应用 + 网络ADB props）+ remotectl 鼠标补丁 + KC2 dts
4. 构建 Docker 镜像（Ubuntu 20.04 + AOSP 依赖，apt 清华源）
5. 内核编译（gcc-10，Image + tinker/kc2 dtb）
6. （full 阶段）Android 11 全量 + Magisk boot 注入

## 已知问题备查

- `repo init` 卡 gerrit.googlesource.com → 必须 `export REPO_URL=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo`（脚本已内置）
- gcc-12 的 `-Warray-parameter` 被按 forbidden 错误 → 必须 `make CC=aarch64-linux-gnu-gcc-10`（命令行级，环境变量无效；同时绕过 gcc-wrapper）
- `make dtbs` 会被树内坏 dts（rk3399-evb-ind-lpddr4-android，sdio0_bus4 坏引用）卡死 → 只编指定 dtb
- 预装 Magisk 管理器 ≠ root；应用级 root 需 boot 注入（脚本 full 阶段已做）
