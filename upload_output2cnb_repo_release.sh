#!/usr/bin/env bash
# =============================================================================
# 上传构建产物到 CNB 仓库 Release 页面
#   https://cnb.cool/xiaoqi-cool/rk3399_androidTV/-/releases
#
# 用法:
#   bash upload_output2cnb_repo_release.sh [kernel|full]   # 默认 kernel
#
# 行为 (实际逻辑在 release_upload.sh, 本脚本是语义化入口):
#   kernel -> Release: kc2-atv11-kernel-日期-短SHA  (Image + rk3399-kc2.dtb + tinker dtb)
#   full   -> Release: kc2-atv11-full-日期-短SHA    (分区镜像 sparse+xz + Magisk boot)
#          -> Release: kc2-atv11-src-日期-短SHA     (整个 AOSP 源码环境分卷 + RESTORE.sh)
#   同时 artifacts 分支 Git LFS 单提交覆盖备份本轮产物
#
# 发布令牌 (任选其一):
#   export CNB_TOKEN=<个人访问令牌>
#   或写入 /workspace/.secrets/cnb_token
# =============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/release_upload.sh" "${1:-kernel}"
