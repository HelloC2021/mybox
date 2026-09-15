FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive

# 可按网络环境换镜像源 (注释默认官方源)
# RUN sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list

# 注意: gcc-aarch64-linux-gnu(gcc-9) 声明 `Conflicts: gcc-multilib` 且与之共享
# libc6-dev-i386。和 gcc-multilib 放在同一条 apt-get install 里会被 apt 解析为
# "not going to be installed" 并 exit 100, 因此必须拆成两条独立的 RUN。
RUN apt-get update && apt-get install -y --no-install-recommends \
    git-core gnupg flex bison gperf build-essential zip curl wget \
    zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
    lib32ncurses-dev x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
    python3 python-is-python3 python3-distutils \
    libssl-dev libncurses5 libncurses5-dev bc rsync file \
    sudo ccache openssh-client \
 && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu \
 && rm -rf /var/lib/apt/lists/*

# repo launcher: 官方下载站 (storage.googleapis.com) 与国内镜像均不可靠, 统一取 GitHub 官方源
RUN curl -fsSL https://raw.githubusercontent.com/GerritCodeReview/git-repo/main/repo \
     -o /usr/local/bin/repo \
 && chmod a+x /usr/local/bin/repo

# 允许容器内 sudo (runner 用户映射)
RUN echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

ENV GIT_EDITOR="true" USE_CCACHE=1
WORKDIR /build
