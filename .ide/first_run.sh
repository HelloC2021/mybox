#!/usr/bin/env bash
# CNB 云开发环境首次进入时的初始化 (对齐 cnbcool/default-dev-env 的 zsh 体验)
# 幂等: 已初始化过则直接跳过
[ -f "$HOME/.cnb-zsh-inited" ] && exit 0

if [ ! -f "$HOME/.zshrc" ]; then
    cp /etc/skel/.zshrc "$HOME/.zshrc" 2>/dev/null || true
fi

# 1) oh-my-zsh + 常用插件
if [ ! -d "$HOME/.oh-my-zsh" ] && command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/github-raw/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        || sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
        || true
    git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" || true
    git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" || true
fi

# 2) 把插件塞进 .zshrc 的 plugins=(...) (幂等)
if [ -f "$HOME/.zshrc" ]; then
    sed -i 's/^[[:space:]]*plugins[[:space:]]*=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
    grep -q 'zsh-autosuggestions' "$HOME/.zshrc" || \
        echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$HOME/.zshrc"
fi

# 3) VS Code Remote-SSH 的 remote-cli 加入 PATH (CNB 默认镜像同款)
if [ -f "$HOME/.zshrc" ] && ! grep -q 'VS_CODE_PATH' "$HOME/.zshrc"; then
    cat >> "$HOME/.zshrc" <<'ZRC'

# 安全地设置 VS_CODE_PATH，兼容未安装 VS Code Server 的情况
code_path=(/root/.vscode-server/cli/servers/*/server/bin/remote-cli/code(N))
if (( ${#code_path[@]} > 0 )); then
  code_path="${code_path[1]}"
  [[ -f "$code_path" ]] && export VS_CODE_PATH="$(dirname "$code_path")"
fi
[ -n "$VS_CODE_PATH" ] && export PATH="$VS_CODE_PATH:$PATH"
ZRC
fi

touch "$HOME/.cnb-zsh-inited"
echo "✅ CNB 开发环境首次初始化完成 (zsh 插件 / VS Code PATH)"
