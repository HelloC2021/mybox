# Self-hosted runner 注册指南（x86 全量 ROM 编译机）

## 硬件核对（你已满足）
- 10 核 / 28GB / 500GB（剩余 ~595GB）✅

## 1. 前置（宿主机，root 执行）
```bash
# Docker (Kali/Ubuntu 通用)
apt update && apt install -y docker.io git
systemctl enable --now docker
# runner 用户加入 docker 组 (如用专用用户)
usermod -aG docker kickpi
# 构建工作目录 (放大盘)
mkdir -p /mnt/aosp && chown $USER /mnt/aosp
```

## 2. 注册 runner
仓库页面 → **Settings → Actions → Runners → New self-hosted runner → Linux x64**，按页面命令执行：

```bash
mkdir actions-runner && cd actions-runner
curl -o runner.tar.gz -L https://github.com/actions/runner/releases/download/v2.3XX/actions-runner-linux-x64-2.3XX.tar.gz
tar xzf ./runner.tar.gz
./config.sh --url https://github.com/HelloC2021/mybox --token <页面自动生成的TOKEN> --labels rom
```
> `--labels rom` 必加（rom.yml 只跑在带 rom 标签的 runner 上）。
> 交互提问直接回车用默认；工作目录选大盘路径。

## 3. 装成服务（开机自启，root）
```bash
cd actions-runner && ./svc.sh install && ./svc.sh start
```

## 4. 设置仓库变量
仓库 → Settings → Secrets and variables → Actions → Variables → New:
- `ROM_ROOT` = `/mnt/aosp`（构建工作目录，按你大盘实际路径）

## 5. 触发编译
仓库 → Actions → **rom** → Run workflow → 选 stage：
- `kernel` — 先验证：同步源码 + 补丁 + 内核/dtb（建议首跑）
- `full` — 完整 ROM + Magisk boot 注入

## 安全提示
公开仓库的 self-hosted runner 会执行仓库 workflow 定义的代码。
本仓库只有 HelloC2021 能 push，风险可控；不放心时用完 `./svc.sh stop` 关掉即可。
