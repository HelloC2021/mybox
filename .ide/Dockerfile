# CNB 云开发环境镜像 (openssh-server 供本地 VSCode Remote-SSH 连接 + 构建依赖预装)
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive

# apt 走清华镜像: 首次 apt 前保持 http (基础镜像未预装 ca-certificates, https 握手会失败)
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list

# openssh-server: CNB 本地 VSCode 远程连接必需
# ca-certificates: 为后续切回 https 源 / repo 下载提供 TLS 证书库
# unzip: build.sh full 阶段 Magisk boot 注入依赖
#
# 注意: aarch64 交叉工具链必须与 gcc-multilib 分两次安装。
# Ubuntu 20.04 中 gcc-9-aarch64-linux-gnu 带 `Conflicts: gcc-multilib` 且与
# gcc-multilib 共享 libc6-dev-i386, 同一次 apt-get install 会被解析成
# "gcc-9-aarch64-linux-gnu : Depends: gcc-9-aarch64-linux-gnu ... not going to be installed"
# 直接 exit 100。分成两条 RUN 后 apt 已锁定 multilib 为手工安装, 不再回滚交叉包。
# 说明: focal 只有 gcc-9-aarch64-linux-gnu (包名 gcc-aarch64-linux-gnu,
# 不存在 gcc-10-aarch64-linux-gnu)。
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server sudo ca-certificates unzip \
    git-core gnupg flex bison gperf build-essential zip curl wget \
    zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
    lib32ncurses-dev x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc fontconfig \
    python3 python-is-python3 python3-distutils \
    libssl-dev libncurses5 libncurses5-dev bc rsync file ccache \
 && rm -rf /var/lib/apt/lists/*

# 32 位 multilib 与 aarch64 交叉工具链分开安装 (见上)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-9-aarch64-linux-gnu \
 && sed -i 's|http://mirrors.tuna.tsinghua.edu.cn|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list \
 && mkdir -p /var/run/sshd \
 && rm -rf /var/lib/apt/lists/*

# 交叉编译器入口 (build.sh 使用 aarch64-linux-gnu-gcc-10 优先, 回退 aarch64-linux-gnu-gcc)
RUN ln -sf /usr/bin/aarch64-linux-gnu-gcc-9 /usr/local/bin/aarch64-linux-gnu-gcc-10

# repo 工具 (清华源, https 失败时走 http 兜底)
RUN curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo \
 || curl -fsSL http://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo \
 && chmod a+x /usr/local/bin/repo

# CNB 会注入 SSH 公钥; 确保 sshd 可启动
RUN sed -i 's/#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true

ENV GIT_EDITOR="true" USE_CCACHE=1
WORKDIR /workspace
