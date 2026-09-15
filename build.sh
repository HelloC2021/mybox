#!/usr/bin/env bash
# =============================================================================
# KC2/K10Plus Android 11 (RK3399) 构建脚本
# 适用: CNB 云原生开发环境 (512G 持久工作区, /workspace) 或任意 Ubuntu x86 主机
# 用法: bash build.sh [kernel|full]     STAGE=环境变量亦可
#
# 增量/幂等设计 (适合手动反复触发):
#   - apt 依赖: .build/apt_done 标记 + 关键工具存在性探测, 已装则秒过
#   - repo sync: 首次全量, 之后增量 (不带 --force-sync, 本地修改的项目自动跳过)
#   - 鼠标补丁: 反向检测已应用则跳过;  kc2.dts: 每次重新生成 (幂等)
#   - 内核: make 增量编译 + ccache (CCACHE_DIR 固定到工作区, 跨次构建复用)
#   - AOSP full: lunch+make 天然增量
#   - 发布: 构建成功后自动发布 Release (无令牌时跳过)
# 依赖网络: apt/repo=清华直连, github 直连 (无代理加速)
# =============================================================================
set -euo pipefail

STAGE="${1:-${STAGE:-kernel}}"
case "$STAGE" in kernel|full) ;; *) echo "用法: bash build.sh [kernel|full]"; exit 1 ;; esac

WS="${WORKSPACE:-/workspace}"
ROOT="$WS/aosp"
MYBOX="$WS/mybox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARK="$WS/.build"                       # 增量构建标记目录 (随工作区持久化)
mkdir -p "$MARK"
DOWNLOAD_JOBS="${DOWNLOAD_JOBS:-8}"     # repo sync / 下载并发数 (直连 github 可按带宽调整)
T0=$(date +%s)

SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo

echo "=== [0/7] 基础依赖 (增量) ==="
# apt 安装是事务性的: 标记存在且关键工具齐全则跳过, 否则重装自愈
if [ -f "$MARK/apt_done" ] && command -v repo >/dev/null 2>&1 \
   && command -v git >/dev/null && command -v python3 >/dev/null \
   && command -v ccache >/dev/null && git lfs version >/dev/null 2>&1 \
   && command -v zstd >/dev/null && command -v unzip >/dev/null; then
    echo "依赖已就绪, 跳过 apt"
else
    if [ -f /etc/apt/sources.list ]; then
        $SUDO sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list || true
    fi
    $SUDO apt-get update
    $SUDO apt-get install -y git python3 python-is-python3 curl wget rsync unzip zip \
        bc bison flex libssl-dev libncurses5 libncurses5-dev ccache sudo git-lfs zstd pigz
    touch "$MARK/apt_done"
fi

# aarch64 交叉工具链:
#   - Ubuntu 20.04(focal) 只有 gcc-9-aarch64-linux-gnu, 并不存在 gcc-10-aarch64-linux-gnu
#     (focal-backports 才有 gcc-10, 默认源里没有), 所以包名固定用 gcc-aarch64-linux-gnu。
#   - gcc-9-aarch64-linux-gnu 声明 `Conflicts: gcc-multilib`, 且两者共享 libc6-dev-i386。
#     若与 gcc-multilib 同一次 apt-get install, apt 会把交叉包解析为
#     "not going to be installed", 直接 exit 100 —— 必须单条命令独立安装。
#   - 镜像 .ide/Dockerfile 已预装该工具链 (单独一条 RUN), 这里只做"已存在则跳过"探测。
CROSS_GCC=""
probe_cross_gcc() {
    for cand in aarch64-linux-gnu-gcc-10 aarch64-linux-gnu-gcc-9 aarch64-linux-gnu-gcc; do
        command -v "$cand" >/dev/null 2>&1 && { CROSS_GCC="$(command -v "$cand")"; return 0; }
    done
    return 1
}
if ! probe_cross_gcc; then
    # 独立的一次 apt 事务: 不要和 gcc-multilib 混在同一条 install 里
    $SUDO apt-get install -y gcc-aarch64-linux-gnu
    probe_cross_gcc || { echo "ERROR: 未找到 aarch64 交叉编译器"; exit 1; }
fi
$SUDO ln -sf "$CROSS_GCC" /usr/local/bin/aarch64-linux-gnu-gcc-cc
CC=aarch64-linux-gnu-gcc-cc
echo "交叉编译器: $CROSS_GCC -> /usr/local/bin/aarch64-linux-gnu-gcc-cc"

# 内核编译启用 ccache (CCACHE_DIR 固定到持久工作区)
CCACHE_BIN=""
if command -v ccache >/dev/null 2>&1; then
    CCACHE_BIN="ccache"
    export CCACHE_DIR="$WS/ccache"
    mkdir -p "$CCACHE_DIR"
fi

which repo >/dev/null 2>&1 || {
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo
    $SUDO chmod a+x /usr/local/bin/repo
}
# repo 工具自身从清华镜像克隆 (gerrit.googlesource.com 被墙)
export REPO_URL=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo

echo "=== [1/7] git 配置 (github 直连) ==="
# 清理历史遗留的 dockermirror insteadOf 重写, 确保全部直连
git config --global --unset-all url."https://dockermirror.truking.top/https://github.com/".insteadOf 2>/dev/null || true
git config --global user.email builder@local
git config --global user.name builder

echo "=== [2/7] mybox 同步 ==="
if [ -d "$MYBOX/.git" ]; then
    (cd "$MYBOX" && git pull --ff-only origin main) || echo "WARN: mybox 更新失败, 沿用本地版本"
else
    git clone https://github.com/HelloC2021/mybox.git "$MYBOX"
fi
# 预装 APK 优先从 GitHub Release 拉取 (full 阶段需要)
if [ "$STAGE" = "full" ]; then
    mkdir -p "$MYBOX/device_overlay/apps"
    for f in AirDroid_4.3.12.0_airdroidhp.apk Magisk-v30.7.apk; do
        [ -s "$MYBOX/device_overlay/apps/$f" ] || curl -fL --retry 3 \
            -o "$MYBOX/device_overlay/apps/$f" \
            "https://github.com/HelloC2021/mybox/releases/download/apps-v1/$f"
    done
fi

echo "=== [3/7] repo 同步 (首次 30~90 分钟, 之后增量) ==="
mkdir -p "$ROOT" && cd "$ROOT"
if [ "${REPO_SYNC:-1}" = "1" ]; then
    if [ ! -d "$ROOT/.repo/manifests" ]; then
        # 首次: 完整初始化 + 全量同步 (并发 DOWNLOAD_JOBS, 直连 github 可调低避免 429/断流)
        repo init -u https://github.com/TinkerBoard-Android/rockchip-android-manifest.git \
            -b android11-rockchip -m tinker_board_2-android11-2.0.8.xml --depth=1
        repo sync -c -j"$DOWNLOAD_JOBS" --fail-fast --prune
    else
        # 增量: 不带 --force-sync —— kernel 等本地有修改的项目自动跳过
        # (避免每次同步抹掉已打的补丁再重打), 其余项目正常更新
        repo sync -c -j"$DOWNLOAD_JOBS" --prune || echo "WARN: 部分项目未同步 (本地有修改已跳过, 属预期)"
    fi
else
    echo "REPO_SYNC=0, 跳过源码同步"
fi

echo "=== [4/7] 定制层 + 补丁 + KC2 dts ==="
rm -rf "$ROOT/device/kc2"
cp -r "$MYBOX/device_overlay" "$ROOT/device/kc2"
cd "$ROOT/kernel"
if git apply --reverse --check --ignore-whitespace "$MYBOX/patches/remotectl_mouse_4.19.patch" 2>/dev/null; then
    echo "鼠标补丁已存在, 跳过"
else
    git apply --ignore-whitespace "$MYBOX/patches/remotectl_mouse_4.19.patch"
fi
cd arch/arm64/boot/dts/rockchip
cp rk3399-tinker-board-2.dts rk3399-kc2.dts
cat "$MYBOX/dts/kc2_override.dts" >> rk3399-kc2.dts

echo "=== [5/7] 内核 + dtb (增量${CCACHE_BIN:+, ccache}) ==="
cd "$ROOT/kernel"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make CC="$CCACHE_BIN $CC" tinker_board_2_defconfig
make CC="$CCACHE_BIN $CC" -j"$(nproc)" Image \
    rockchip/rk3399-tinker-board-2.dtb rockchip/rk3399-kc2.dtb \
    KCFLAGS="-Wno-error"

echo "=== [6/7] 产物 ==="
mkdir -p "$WS/out"
cp "$ROOT/kernel/arch/arm64/boot/Image" "$WS/out/" 2>/dev/null || true
find "$ROOT/kernel/arch/arm64/boot/dts" -name 'rk3399-kc2.dtb' \
    -exec cp {} "$WS/out/" \; 2>/dev/null || true
find "$ROOT/kernel/arch/arm64/boot/dts" -name 'rk3399-tinker-board-2.dtb' \
    -exec cp {} "$WS/out/" \; 2>/dev/null || true
ls -la "$WS/out/"

if [ "$STAGE" = "full" ]; then
    echo "=== [full] Android 11 全量 (增量) ==="
    cd "$ROOT"
    source build/envsetup.sh
    lunch tinker_board_2-userdebug
    make -j"$(nproc)"
    OUT="$ROOT/out/target/product/tinker_board_2"
    echo "=== [full] Magisk boot 注入 (应用级 root) ==="
    MG="$WS/magisk"; mkdir -p "$MG" && cd "$MG"
    unzip -o "$MYBOX/device_overlay/apps/Magisk-v30.7.apk" -d apk >/dev/null
    export MAGISKBIN="$PWD/apk/lib/arm64-v8a"
    cp apk/lib/x86_64/libmagiskboot.so magiskboot && chmod +x magiskboot
    export KEEPVERITY=true KEEPFORCEENCRYPT=true
    sh apk/assets/boot_patch.sh "$OUT/boot.img" || true
    ls -la "$OUT"/boot.img*
    echo "=== full 阶段产物: $OUT ==="
fi

# ===========================================================================
# [7/7] 发布提示 (不自动上传; 需要时手动执行发布脚本)
# ===========================================================================
echo
echo "======================================================================="
echo " 构建完成, 可手动发布产物到 CNB Release 页面:"
echo "   bash $SCRIPT_DIR/upload_output2cnb_repo_release.sh $STAGE"
echo " 产物位置:"
if [ "$STAGE" = "full" ]; then
    echo "   - 分区镜像/Magisk boot: $ROOT/out/target/product/tinker_board_2"
fi
echo "   - 内核产物 (Image + dtb): $WS/out"
echo "======================================================================="

echo "=== BUILD DONE ($STAGE), 耗时 $(( $(date +%s) - T0 ))s ==="
