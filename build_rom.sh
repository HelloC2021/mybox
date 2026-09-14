#!/bin/bash
# KC2/K10Plus Android 11 ROM 本地构建脚本
# 用法: build_rom.sh [kernel|full]    (默认 kernel)
# 持久源码树: /mnt/data/aosp  |  mybox: /mnt/data/mybox
set -e

STAGE=${1:-kernel}
ROOT=/mnt/data/aosp
MYBOX=/mnt/data/mybox
PROXY=http://192.168.199.67:10808

# 代理仅给 git/repo (github 流量)
git config --global http.proxy $PROXY
git config --global https.proxy $PROXY
git config --global user.email builder@local
git config --global user.name builder
# repo 工具自身改从清华镜像克隆 (gerrit.googlesource.com 被墙)
export REPO_URL=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo

echo "== [1/6] mybox 同步 =="
[ -d $MYBOX/.git ] || git clone https://github.com/HelloC2021/mybox.git $MYBOX
cd $MYBOX && git pull --ff-only origin main

echo "== [2/6] repo 同步 (首次完整, 之后增量) =="
mkdir -p $ROOT && cd $ROOT
if [ ! -d .repo/manifests ]; then
    repo init -u https://github.com/TinkerBoard2-Android/manifest.git \
        -b android11-rk3399 -m tinker_board_2-android11-2.0.1.xml --depth=1
fi
repo sync -c -j8 --fail-fast

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
