#!/bin/bash
# KC2/K10Plus Android 11 ROM 本地构建脚本
# 用法: build_rom.sh [kernel|full]    (默认 kernel)
# 持久源码树: /mnt/data/aosp  |  mybox: /mnt/data/mybox
set -e

STAGE=${1:-kernel}
ROOT=/mnt/data/aosp
MYBOX=/mnt/data/mybox
# github 全部走 dockermirror 加速 (不经代理); AOSP googlesource 走清华
git config --global url."https://dockermirror.truking.top/https://github.com/".insteadOf "https://github.com/"
git config --global url."https://aosp.tuna.tsinghua.edu.cn/".insteadOf "https://android.googlesource.com/"
git config --global user.email builder@local
git config --global user.name builder
# repo 工具源码走 GitHub 官方源 (gerrit.googlesource.com 被墙; 国内镜像 git 服务有排队限流)
export REPO_URL="${REPO_URL:-https://github.com/GerritCodeReview/git-repo}"

echo "== [1/6] mybox 同步 =="
git config --global user.email builder@local
git config --global user.name builder
[ -d $MYBOX/.git ] || git clone https://github.com/HelloC2021/mybox.git $MYBOX
cd $MYBOX && git pull --ff-only origin main

echo "== [2/6] repo 同步 (首次完整, 之后增量) =="
mkdir -p $ROOT && cd $ROOT
repo init -u https://github.com/TinkerBoard-Android/rockchip-android-manifest.git \
    -b android11-rockchip -m tinker_board_2-android11-2.0.8.xml --depth=1
# 网络不稳定: 交替使用 dockermirror / github 直连, 断点续传直至完成
sync_ok=0
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12; do
    case $((attempt % 3)) in
      1) git config --global url."https://dockermirror.truking.top/https://github.com/".insteadOf "https://github.com/" || true
         git config --global --unset http.proxy 2>/dev/null || true
         echo "--- sync attempt $attempt (dockermirror) ---" ;;
      2) git config --global --unset-all url.*.insteadof 2>/dev/null || true
         git config --global http.proxy http://192.168.199.67:10808
         echo "--- sync attempt $attempt (proxy 10808) ---" ;;
      0) git config --global --unset-all url.*.insteadof 2>/dev/null || true
         git config --global --unset http.proxy 2>/dev/null || true
         echo "--- sync attempt $attempt (direct github) ---" ;;
    esac
    # googlesource 被墙: 每次尝试都确保 AOSP 补充仓库走清华
    git config --global url."https://aosp.tuna.tsinghua.edu.cn/".insteadOf "https://android.googlesource.com/"
    if repo sync -c -j8 --force-sync --prune; then
        sync_ok=1
        break
    fi
    sleep 20
done
[ "$sync_ok" = 1 ] || { echo "sync 最终失败"; exit 1; }

echo "== [3/6] 定制层 + 补丁 =="
rm -rf $ROOT/device/kc2
cp -r $MYBOX/device_overlay $ROOT/device/kc2
cd $ROOT/kernel
if git apply --reverse --check --ignore-whitespace $MYBOX/patches/remotectl_mouse_4.19.patch 2>/dev/null; then
    echo "鼠标补丁已存在, 跳过"
else
    git apply --ignore-whitespace $MYBOX/patches/remotectl_mouse_4.19.patch
fi
cd arch/arm64/boot/dts/rockchip
cp rk3399-tinker-board-2.dts rk3399-kc2.dts
cat $MYBOX/dts/kc2_override.dts >> rk3399-kc2.dts

echo "== [4/6] 构建镜像 =="
docker build -t kc2-aosp11 - < $MYBOX/Dockerfile

echo "== [5/6] 内核 + dtb =="
mkdir -p /mnt/data/ccache
docker run --rm -v $ROOT:/build -v /mnt/data/ccache:/build/.ccache kc2-aosp11 bash -c '
    cd /build/kernel && export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
    make CC=aarch64-linux-gnu-gcc-10 tinker_board_2_defconfig
    make CC=aarch64-linux-gnu-gcc-10 -j$(nproc) Image \
      rockchip/rk3399-tinker-board-2.dtb rockchip/rk3399-kc2.dtb'
mkdir -p /mnt/data/out
cp $ROOT/kernel/arch/arm64/boot/Image /mnt/data/out/ 2>/dev/null || true
find $ROOT/kernel/arch/arm64/boot/dts -name '*.dtb' -newer $MYBOX/dts/kc2_override.dts -exec cp {} /mnt/data/out/ \; 2>/dev/null || true

if [ "$STAGE" = "full" ]; then
    echo "== [6/6] 完整 ROM =="
    docker run --rm -v $ROOT:/build kc2-aosp11 bash -c '
        cd /build && source build/envsetup.sh &&
        lunch tinker_board_2-userdebug && make -j$(nproc)'
    OUT=$ROOT/out/target/product/tinker_board_2
    mkdir -p /mnt/data/magisk && cd /mnt/data/magisk
    unzip -o $MYBOX/device_overlay/apps/Magisk-v30.7.apk -d apk >/dev/null
    export MAGISKBIN=$PWD/apk/lib/arm64-v8a
    cp apk/lib/x86_64/libmagiskboot.so magiskboot && chmod +x magiskboot
    export KEEPVERITY=true KEEPFORCEENCRYPT=true
    sh apk/assets/boot_patch.sh "$OUT/boot.img" || true
    ls -la $OUT/boot.img*
fi

echo "=== BUILD DONE ($STAGE) ==="
