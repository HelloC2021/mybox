#!/usr/bin/env bash
# =============================================================================
# KC2/K10Plus Android 11 (RK3399) 构建脚本
# 适用: CNB 云原生构建 (Ubuntu 20.04 容器, /workspace 512G) 或任意 Ubuntu x86 主机
# 用法: bash build.sh [kernel|full]     STAGE=环境变量亦可
# 依赖网络: 全部国内直连 (apt/repo=清华, github=dockermirror), 无需代理
# =============================================================================
set -euo pipefail

STAGE="${1:-${STAGE:-kernel}}"
WS="${WORKSPACE:-/workspace}"
ROOT="$WS/aosp"
MYBOX="$WS/mybox"
MIRROR="https://dockermirror.truking.top/https://github.com/"

SUDO=""; [ "$(id -u)" = 0 ] || SUDO=sudo

echo "=== [0/6] 基础依赖 (清华源直连) ==="
if [ -f /etc/apt/sources.list ]; then
    $SUDO sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list || true
fi
$SUDO apt-get update
$SUDO apt-get install -y git python3 python-is-python3 curl wget rsync unzip zip \
    bc bison flex libssl-dev libncurses5 libncurses5-dev ccache sudo

# aarch64 交叉工具链:
#   - Ubuntu 20.04(focal) 只有 gcc-9-aarch64-linux-gnu, 并不存在 gcc-10-aarch64-linux-gnu
#     (focal-backports 才有 gcc-10, 默认源里没有), 所以包名固定用 gcc-aarch64-linux-gnu。
#   - gcc-9-aarch64-linux-gnu 声明 `Conflicts: gcc-multilib`, 且两者共享 libc6-dev-i386。
#     若与 gcc-multilib 同一次 apt-get install, apt 会把交叉包解析为
#     "not going to be installed", 直接 exit 100 —— 必须单条命令独立安装。
#   - 镜像 .ide/Dockerfile 已预装该工具链 (单独一条 RUN), 这里只做"已存在则跳过"探测。
CROSS_GCC=""
for cand in aarch64-linux-gnu-gcc-10 aarch64-linux-gnu-gcc-9 aarch64-linux-gnu-gcc; do
    command -v "$cand" >/dev/null 2>&1 && { CROSS_GCC="$(command -v "$cand")"; break; }
done
if [ -z "$CROSS_GCC" ]; then
    # 独立的一次 apt 事务: 不要和 gcc-multilib 混在同一条 install 里
    $SUDO apt-get install -y gcc-aarch64-linux-gnu
    for cand in aarch64-linux-gnu-gcc-10 aarch64-linux-gnu-gcc-9 aarch64-linux-gnu-gcc; do
        command -v "$cand" >/dev/null 2>&1 && { CROSS_GCC="$(command -v "$cand")"; break; }
    done
fi
[ -n "$CROSS_GCC" ] || { echo "ERROR: 未找到 aarch64 交叉编译器"; exit 1; }
$SUDO ln -sf "$CROSS_GCC" /usr/local/bin/aarch64-linux-gnu-gcc-cc
CC=aarch64-linux-gnu-gcc-cc
echo "交叉编译器: $CROSS_GCC -> /usr/local/bin/aarch64-linux-gnu-gcc-cc"

which repo >/dev/null 2>&1 || {
    curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo
    $SUDO chmod a+x /usr/local/bin/repo
}

echo "=== [1/6] git 配置 (github 走 dockermirror, 无需代理) ==="
git config --global url."https://dockermirror.truking.top/https://github.com/".insteadOf "https://github.com/"
git config --global user.email builder@local
git config --global user.name builder

echo "=== [2/6] mybox 同步 ==="
if [ -d "$MYBOX/.git" ]; then
    cd "$MYBOX" && git pull --ff-only origin main || true
else
    git clone https://github.com/HelloC2021/mybox.git "$MYBOX"
    cd "$MYBOX"
fi
# 预装 APK 优先从 GitHub Release 拉取 (full 阶段需要)
if [ "$STAGE" = "full" ]; then
    mkdir -p device_overlay/apps
    for f in AirDroid_4.3.12.0_airdroidhp.apk Magisk-v30.7.apk; do
        [ -s "device_overlay/apps/$f" ] || curl -fL --retry 3 \
            -o "device_overlay/apps/$f" \
            "https://github.com/HelloC2021/mybox/releases/download/apps-v1/$f"
    done
fi

echo "=== [3/6] repo 同步 (首次 30~90 分钟, 之后增量) ==="
mkdir -p "$ROOT" && cd "$ROOT"
# 无条件执行 repo init: 幂等, 且能自愈上次中断留下的残缺 .repo
repo init -u https://github.com/TinkerBoard-Android/rockchip-android-manifest.git \
    -b android11-rockchip -m tinker_board_2-android11-2.0.8.xml --depth=1
repo sync -c -j8 --fail-fast --force-sync --prune

echo "=== [4/6] 定制层 + 补丁 + KC2 dts ==="
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

echo "=== [5/6] 内核 + dtb ==="
mkdir -p "$WS/ccache"
docker_not_used=1
cd "$ROOT/kernel"
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
make CC="$CC" tinker_board_2_defconfig
make CC="$CC" -j"$(nproc)" Image \
    rockchip/rk3399-tinker-board-2.dtb rockchip/rk3399-kc2.dtb \
    KCFLAGS="-Wno-error"

echo "=== [6/6] 产物 ==="
mkdir -p "$WS/out"
cp "$ROOT/kernel/arch/arm64/boot/Image" "$WS/out/" 2>/dev/null || true
find "$ROOT/kernel/arch/arm64/boot/dts" -name 'rk3399-kc2.dtb' \
    -exec cp {} "$WS/out/" \; 2>/dev/null || true
find "$ROOT/kernel/arch/arm64/boot/dts" -name 'rk3399-tinker-board-2.dtb' \
    -exec cp {} "$WS/out/" \; 2>/dev/null || true
ls -la "$WS/out/"

if [ "$STAGE" = "full" ]; then
    echo "=== [full] Android 11 全量 ==="
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

echo "=== BUILD DONE ($STAGE) ==="
