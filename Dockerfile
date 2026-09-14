FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive

# 可按网络环境换镜像源 (注释默认官方源)
# RUN sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    git-core gnupg flex bison gperf build-essential zip curl wget \
    zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
    lib32ncurses-dev x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc unzip fontconfig \
    python3 python-is-python3 python3-distutils \
    libssl-dev libncurses5 libncurses5-dev bc rsync file \
    gcc-10-aarch64-linux-gnu sudo ccache openssh-client \
 && rm -rf /var/lib/apt/lists/*

# repo 工具 (github 源可达时用官方; 不通时用清华镜像二选一)
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
 && chmod a+x /usr/local/bin/repo \
 || (curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo \
 && chmod a+x /usr/local/bin/repo)

# 允许容器内 sudo (runner 用户映射)
RUN echo "root ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# 编译加速代理 (局域网代理机, repo/git/apt 走它)
RUN git config --global http.proxy http://192.168.199.67:10808  && git config --global https.proxy http://192.168.199.67:10808
ENV HTTP_PROXY=http://192.168.199.67:10808 HTTPS_PROXY=http://192.168.199.67:10808
ENV NO_PROXY=localhost,127.0.0.1
ENV GIT_EDITOR="true" USE_CCACHE=1
WORKDIR /build
