# CNB 云开发环境镜像
#   - 对齐 CNB 默认镜像 cnbcool/default-dev-env 的必备组件 (code-server + 插件 + codebuddy + node)
#   - 满足 RK3399 / Android 11 编译依赖 (repo / ccache / aarch64 交叉工具链)
#   - openssh-server 供本地 VSCode / Cursor / CodeBuddy 客户端 Remote-SSH 连接
FROM ubuntu:20.04
ENV DEBIAN_FRONTEND=noninteractive

# apt 走清华镜像: 首次 apt 前保持 http
# (ubuntu:20.04 未预装 ca-certificates, 直接用 https 源会 TLS 握手失败 exit 100)
RUN sed -i 's|http://archive.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g; s|http://security.ubuntu.com|http://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list

# --- 基础工具 + Android 编译依赖 + CNB 默认镜像同款基础件 ---
# openssh-server : 本地 VSCode Remote-SSH 连接必需
# ca-certificates: 为后续切 https 源 / code-server 安装提供 TLS 证书库
# unzip          : build.sh full 阶段 Magisk boot 注入依赖
# zsh/locales    : CNB 默认镜像同款, 交互终端 + 中文 locale (消除 setlocale 告警与中文乱码)
# vim/jq/git-lfs : CNB 默认镜像同款基础工具
#
# 注意: aarch64 交叉工具链必须与 gcc-multilib 分两次安装。
# Ubuntu 20.04 中 gcc-9-aarch64-linux-gnu 带 `Conflicts: gcc-multilib` 且与
# gcc-multilib 共享 libc6-dev-i386, 同一次 apt-get install 会被解析成
# "not going to be installed" 直接 exit 100。分成两条 RUN 后 apt 已锁定
# multilib 为手工安装, 不再回滚交叉包。
# 说明: focal 只有 gcc-9-aarch64-linux-gnu (包名 gcc-aarch64-linux-gnu)。
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server sudo ca-certificates unzip \
    git-core git-lfs gnupg flex bison gperf build-essential zip curl wget \
    zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
    lib32ncurses-dev x11proto-core-dev libx11-dev lib32z1-dev \
    libgl1-mesa-dev libxml2-utils xsltproc fontconfig \
    python3 python-is-python3 python3-distutils \
    libssl-dev libncurses5 libncurses5-dev bc rsync file ccache \
    vim jq gettext-base xz-utils lsof htop net-tools dnsutils nload zsh locales \
 && git lfs install --system \
 && sed -i 's/^# *\(zh_CN.UTF-8\)/\1/; s/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
 && locale-gen zh_CN.UTF-8 en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

# 32 位 multilib 与 aarch64 交叉工具链分开安装 (见上)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc-9-aarch64-linux-gnu \
 && sed -i 's|http://mirrors.tuna.tsinghua.edu.cn|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list \
 && mkdir -p /var/run/sshd \
 && rm -rf /var/lib/apt/lists/*

# 交叉编译器入口 (build.sh 使用 aarch64-linux-gnu-gcc-10 优先, 回退 aarch64-linux-gnu-gcc)
RUN ln -sf /usr/bin/aarch64-linux-gnu-gcc-9 /usr/local/bin/aarch64-linux-gnu-gcc-10

# --- Node.js 22 (CNB 默认镜像同款版本) + CNB CLI / CodeBuddy ---
# codebuddy (>= 2.137.0) 是 CodeBuddy Web 入口与 CodeBuddy 面板的前置条件
ENV NODE_VERSION=22.23.1
RUN ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m) && \
    case "$ARCH" in \
      amd64|x86_64) NODE_ARCH=x64 ;; \
      arm64|aarch64) NODE_ARCH=arm64 ;; \
      *) echo "unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
 || curl -fsSLO "https://mirrors.tuna.tsinghua.edu.cn/nodejs-release/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
 && tar -xJf "node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -C /usr/local --strip-components=1 --no-same-owner \
 && rm -f "node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" \
 && node -v && npm -v \
 && npm install -g @tencent-ai/codebuddy-code@latest @cnbcool/cnb-cli

# --- code-server (WebIDE) + 必备 VSCode 插件 (对齐 CNB 默认镜像) ---
# cnbcool.cnb-welcome 提供「CNB 开发」面板; tencent-cloud.coding-copilot 提供 CodeBuddy 面板
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version 4.117.0 \
 && code-server --install-extension cnbcool.cnb-welcome \
 && code-server --install-extension redhat.vscode-yaml \
 && code-server --install-extension mhutchie.git-graph \
 && code-server --install-extension donjayamanne.githistory \
 && code-server --install-extension cloudstudio.live-server \
 && code-server --install-extension tencent-cloud.coding-copilot \
 && code-server --install-extension bierner.markdown-mermaid \
 && echo done

# --- repo 工具 (清华源, https 失败时走 http 兜底) ---
RUN curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo \
 || curl -fsSL http://mirrors.tuna.tsinghua.edu.cn/git/git-repo -o /usr/local/bin/repo \
 && chmod a+x /usr/local/bin/repo

# --- CNB 开发环境机器级配置 (code-server / VSCode Remote-SSH 共用) ---
COPY settings.json /root/.vscode-server/data/Machine/settings.json
COPY settings.json /root/.local/share/code-server/Machine/settings.json
COPY first_run.sh /usr/local/bin/cnb-first-run
RUN chmod +x /usr/local/bin/cnb-first-run

# CNB 会注入 SSH 公钥; 确保 sshd 可启动
RUN sed -i 's/#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || true

# 交互式 shell (含 zsh / ssh) 也能找到 /usr/local/bin 下的 node/npm/codebuddy
ENV PATH=/usr/local/bin:$PATH
# 中文 locale: 使 VSCode Remote-SSH 集成终端可直接输入中文 (与 CNB 默认镜像一致)
ENV LANG=zh_CN.UTF-8
ENV LC_ALL=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:en_US

ENV GIT_EDITOR="true" USE_CCACHE=1
WORKDIR /workspace
