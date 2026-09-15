#!/usr/bin/env bash
# =============================================================================
# 构建产物发布脚本 (仅在 CNB 流水线内可用)
#
# 职责:
#   1. 收集 kernel / full 阶段产物到 release_assets/<tag>/
#      大镜像 (>256MB) 先转 sparse 再 xz 压缩, 控制单次发布体积
#   2. full 阶段额外把整个 AOSP 源码环境 (含 .repo, 排除 out/) 打包成
#      4GiB 分卷 + zstd 压缩, 推到独立的 src-<tag> Release (附还原脚本),
#      后续构建可直接解包恢复环境, 跳过 30~90 分钟的 repo sync
#   3. Release 保留策略: 自动删除超出保留数的旧版本释放空间
#      (产物 RELEASES_KEEP=5; 源码环境 RELEASES_KEEP_SRC=1)
#   4. 产物经 Git LFS 单提交覆盖推送到 artifacts 分支 (仓库配额内的小备份)
#
# 注意: CNB 两类存储额度分开计费 (各 100GiB/月, 超出 1 元/GiB/月)
#   仓库存储 = Git 对象          -> 本仓库仅数百 KB, 无压力
#   对象存储 = 制品/LFS/附件      -> Release 附件与 artifacts 分支的 LFS 对象都算这里
# 所以大体积内容仍应走 Release (不占 Git 对象), 但必须严格控制保留份数。
#
# 用法: bash release_upload.sh [kernel|full]
# 依赖: CNB_TOKEN / CNB_REPO_SLUG / CNB_API_ENDPOINT (流水线内置), python3, git-lfs, zstd
# =============================================================================
set -euo pipefail

STAGE="${1:-${STAGE:-kernel}}"
WS="${WORKSPACE:-/workspace}"          # CNB_BUILD_WORKSPACE, build.sh 的产物/源码树所在
ROOT="$WS/aosp"
OUT="$WS/out"                          # kernel 阶段产物目录
AOSP_OUT="$ROOT/out/target/product/tinker_board_2"

REPO="${CNB_REPO_SLUG:-}"
if [ -z "$REPO" ]; then
    # 手动场景 (云开发终端): 从仓库 checkout 的 origin 远端推导 slug
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _remote=$(git -C "$_SCRIPT_DIR" remote get-url origin 2>/dev/null || true)
    REPO=$(printf '%s' "$_remote" | sed -E 's#^https?://[^/]+/##; s#\.git$##; s#^git@[^:]+:##')
fi
[ -n "$REPO" ] || { echo "ERROR: 无法确定仓库 slug (设置 CNB_REPO_SLUG 或检查 git remote)"; exit 1; }

# 令牌优先级: CNB_TOKEN > $CNB_TOKEN_FILE > /workspace/.secrets/cnb_token > ~/.cnb_token
TOKEN="${CNB_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -n "${CNB_TOKEN_FILE:-}" ] && [ -s "$CNB_TOKEN_FILE" ]; then
    TOKEN=$(cat "$CNB_TOKEN_FILE")
fi
if [ -z "$TOKEN" ]; then
    for _tf in "$WS/.secrets/cnb_token" "$HOME/.cnb_token"; do
        [ -s "$_tf" ] && { TOKEN=$(cat "$_tf"); break; }
    done
fi
[ -n "$TOKEN" ] || {
    echo "ERROR: 未找到 CNB 访问令牌。任选其一:"
    echo "  1. export CNB_TOKEN=<个人访问令牌>"
    echo "  2. 将令牌写入 /workspace/.secrets/cnb_token (已在 .gitignore 中排除)"
    echo "     令牌创建: cnb.cool -> 个人设置 -> 访问令牌 (需 repo-code:rw / Release 权限)"
    exit 1
}
export CNB_TOKEN="$TOKEN"

API="${CNB_API_ENDPOINT:-https://api.cnb.cool}"
SHORT="${CNB_COMMIT_SHORT:-manual}"
TAG="${RELEASE_TAG:-kc2-atv11-$STAGE-$(date +%Y%m%d)-$SHORT}"

RELEASES_KEEP="${RELEASES_KEEP:-5}"        # 产物 Release 保留数 (kc2-atv11-kernel/full-*)
RELEASES_KEEP_SRC="${RELEASES_KEEP_SRC:-1}"  # 源码环境 Release 保留数 (kc2-atv11-src-*)
COMPRESS_MIN_BYTES="${COMPRESS_MIN_BYTES:-268435456}"  # >256MB 的镜像才压缩
SOURCE_PACK="${SOURCE_PACK:-1}"            # full 阶段是否打包源码环境 (1=是)
SPLIT_BYTES="${SPLIT_BYTES:-4294967296}"   # 源码分卷大小 (默认 4GiB)

command -v python3 >/dev/null || { echo "ERROR: 需要 python3"; exit 1; }
command -v git >/dev/null && git lfs version >/dev/null 2>&1 \
    || { echo "ERROR: 需要 git-lfs"; exit 1; }

jget() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get(sys.argv[1],""))' "$1"; }

AUTH=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/json")

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

# 上传一个目录下所有文件为指定 release 的附件 (先创建/复用 release)
upload_dir_as_release() {   # $1=release目录  $2=tag  $3=release标题前缀描述
    local DIR="$1" RTAG="$2" RDESC="$3"
    local REL RID f NAME SZ RESP UPLOAD_URL VERIFY_URL

    REL=$(curl -fsS "${AUTH[@]}" "$API/$REPO/-/releases/tags/$RTAG" 2>/dev/null || true)
    if [ -z "$REL" ]; then
        local PAYLOAD=$(mktemp)
        python3 -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({
            "tag_name": sys.argv[2], "name": sys.argv[2],
            "body": sys.argv[3], "target_commitish": sys.argv[4] or None,
            "make_latest": "true"}))' "$PAYLOAD" "$RTAG" "$RDESC" "${CNB_COMMIT:-}"
        REL=$(curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' \
            --data-binary @"$PAYLOAD" "$API/$REPO/-/releases")
        rm -f "$PAYLOAD"
        echo "Release 已创建: $RTAG"
    else
        echo "Release 已存在, 覆盖上传附件: $RTAG"
    fi
    RID=$(printf '%s' "$REL" | jget id)
    [ -n "$RID" ] || { echo "ERROR: 未取到 release id ($RTAG)"; exit 1; }

    for f in "$DIR"/*; do
        [ -f "$f" ] || continue
        NAME=$(basename "$f")
        SZ=$(stat -c%s "$f")
        RESP=$(curl -fsS -X POST "${AUTH[@]}" -H 'Content-Type: application/json' \
            -d "{\"asset_name\":\"$NAME\",\"size\":$SZ,\"overwrite\":true}" \
            "$API/$REPO/-/releases/$RID/asset-upload-url")
        UPLOAD_URL=$(printf '%s' "$RESP" | jget upload_url)
        VERIFY_URL=$(printf '%s' "$RESP" | jget verify_url)
        [ -n "$UPLOAD_URL" ] && [ -n "$VERIFY_URL" ] \
            || { echo "ERROR: $NAME 未取得上传地址: $RESP"; exit 1; }
        # 预签名上传: 优先 PUT, 失败回退 POST; 网络抖动重试 3 次
        local ok=0
        for i in 1 2 3; do
            if curl -fsS -X PUT --upload-file "$f" "$UPLOAD_URL" \
               && curl -fsS -X POST "${AUTH[@]}" "${VERIFY_URL}?ttl=0" >/dev/null; then
                ok=1; break
            fi
            echo "  上传失败, 重试 $i/3: $NAME"
            sleep $((i * 10))
        done
        [ "$ok" = 1 ] || { echo "ERROR: 附件上传失败: $NAME"; exit 1; }
        echo "  OK: $NAME ($(numfmt --to=iec "$SZ" 2>/dev/null || echo "${SZ}B"))"
    done
}

# 保留策略: 删除 tag 以 $2 开头且超出 $3 个之外的旧 Release
prune_releases() {          # $1=tag前缀  $2=保留数
    local PREFIX="$1" KEEP="$2"
    [ "$KEEP" -ge 1 ] || return 0
    python3 - "$API" "$REPO" "$PREFIX" "$KEEP" <<'PY' | while read -r RID RTAG; do
import json, subprocess, sys
api, repo, prefix, keep = sys.argv[1:5]
auth = ["-H", "Authorization: Bearer " + __import__("os").environ["CNB_TOKEN"],
        "-H", "Accept: application/json"]
tags = []
page = 1
while page <= 20:
    r = subprocess.run(["curl", "-fsS", *auth,
        f"{api}/{repo}/-/releases?page={page}&page_size=100"],
        capture_output=True, text=True)
    if r.returncode != 0: break
    batch = json.loads(r.stdout) if r.stdout.strip() else []
    if not batch: break
    for rel in batch:
        if str(rel.get("tag_name", "")).startswith(prefix):
            tags.append((rel["id"], rel["tag_name"]))
    page += 1
for rid, tag in tags[int(keep):]:
    print(rid, tag)
PY
        echo "  清理旧 Release: $RTAG (超出保留数 $KEEP)"
        curl -fsS -X DELETE "${AUTH[@]}" "$API/$REPO/-/releases/$RID" >/dev/null || true
    done
}

# 大文件压缩: 已是 sparse 则直接 xz; raw ext4 先 img2simg 再 xz
compress_big_file() {       # $1=文件
    local f="$1" SZ IMG2SIMG="$ROOT/out/host/linux-x86/bin/img2simg" sparse
    SZ=$(stat -c%s "$f")
    [ "$SZ" -gt "$COMPRESS_MIN_BYTES" ] || return 0
    # Android sparse 魔数 0xED26FF3A 位于偏移 4 (小端)
    if python3 -c 'import sys; f=open(sys.argv[1],"rb"); f.seek(4); sys.exit(0 if f.read(4)==b"\x3a\xff\x26\xed" else 1)' "$f"; then
        sparse=1
    elif [ -x "$IMG2SIMG" ]; then
        echo "  sparse 化: $(basename "$f")"
        "$IMG2SIMG" "$f" "$f.sparse" && mv "$f.sparse" "$f"
        sparse=1
    else
        sparse=0
    fi
    echo "  xz 压缩: $(basename "$f") ($SZ -> 压缩中)"
    xz -T0 -q -f "$f"
    echo "  压缩完成: $(basename "$f").xz ($(stat -c%s "$f.xz")B)"
}

# ---------------------------------------------------------------------------
# 1. 收集产物
# ---------------------------------------------------------------------------
echo "=== [release/1] 收集产物 (stage=$STAGE tag=$TAG) ==="
STAGE_DIR="$WS/release_assets/$TAG"
rm -rf "$STAGE_DIR" && mkdir -p "$STAGE_DIR"

if [ "$STAGE" = "kernel" ]; then
    [ -s "$OUT/Image" ] && cp -v "$OUT/Image" "$STAGE_DIR/" || echo "WARN: 未找到 Image"
    find "$ROOT/kernel/arch/arm64/boot/dts" \
        \( -name 'rk3399-kc2.dtb' -o -name 'rk3399-tinker-board-2.dtb' \) \
        -exec cp -v {} "$STAGE_DIR/" \; 2>/dev/null || true
else
    # full: AOSP 关键分区镜像 + Magisk patched boot + 内核产物
    for f in boot.img system.img vendor.img product.img odm.img recovery.img; do
        [ -s "$AOSP_OUT/$f" ] && cp -v "$AOSP_OUT/$f" "$STAGE_DIR/" || true
    done
    for f in "$AOSP_OUT"/magisk_patched-*.img; do
        [ -s "$f" ] && cp -v "$f" "$STAGE_DIR/" || true
    done
    for f in "$OUT"/Image "$OUT"/*.dtb; do
        [ -s "$f" ] && cp -v "$f" "$STAGE_DIR/" || true
    done
fi

echo "=== [release/1.5] 大文件 sparse+xz 压缩 ==="
for f in "$STAGE_DIR"/*; do
    [ -f "$f" ] && compress_big_file "$f" || true
done

N_FILES=$(find "$STAGE_DIR" -type f | wc -l)
[ "$N_FILES" -gt 0 ] || { echo "ERROR: 没有任何产物可发布"; exit 1; }
echo "共 $N_FILES 个文件:"; ls -lh "$STAGE_DIR"

# ---------------------------------------------------------------------------
# 2. full: 整个 AOSP 源码环境打包 (分卷 + 压缩), 走 Release 大文件通道
# ---------------------------------------------------------------------------
SRC_TAG=""
if [ "$STAGE" = "full" ] && [ "$SOURCE_PACK" = "1" ] && [ -d "$ROOT/.repo" ]; then
    SRC_TAG="kc2-atv11-src-$(date +%Y%m%d)-$SHORT"
    SRC_DIR="$WS/release_assets/$SRC_TAG"
    rm -rf "$SRC_DIR" && mkdir -p "$SRC_DIR"
    echo "=== [release/2] 源码环境打包 -> $SRC_TAG (含 .repo, 排除 out/; 耗时较长) ==="

    # 压缩程序选择: zstd > pigz > gzip
    local_suffix="tar"; local_prog=""
    if command -v zstd >/dev/null; then
        local_prog="zstd -T0 -2"; local_suffix="tar.zst"
    elif command -v pigz >/dev/null; then
        local_prog="pigz -1"; local_suffix="tar.gz"
    else
        local_prog="gzip -1"
    fi

    (cd "$WS" && tar --use-compress-program="$local_prog" \
        --exclude='aosp/out' \
        --exclude='aosp/.ccache' \
        -cf - aosp) \
        | split -b "$SPLIT_BYTES" - "$SRC_DIR/aosp-src.$local_suffix.part-"

    # 还原脚本 + 校验清单
    cat > "$SRC_DIR/RESTORE.sh" <<EOF
#!/usr/bin/env bash
# KC2 AOSP 源码环境还原: 下载本 Release 全部分卷与本脚本到同一目录后执行
# 用法: bash RESTORE.sh [目标目录, 默认 /workspace]
set -e
DEST="\${1:-/workspace}"
SUFFIX="$local_suffix"
echo "== 校验 SHA256 (分卷) =="
sha256sum -c aosp-src.sha256
echo "== 合并分卷 -> aosp-src.\$SUFFIX =="
cat aosp-src.\$SUFFIX.part-* > "\$DEST/aosp-src.\$SUFFIX"
echo "== 解压到 \$DEST =="
case "\$SUFFIX" in
  tar.zst) tar --use-compress-program="zstd -T0" -xf "\$DEST/aosp-src.\$SUFFIX" -C "\$DEST" ;;
  *)       tar -xf "\$DEST/aosp-src.\$SUFFIX" -C "\$DEST" ;;
esac
rm -f "\$DEST/aosp-src.\$SUFFIX"
echo "完成: \$DEST/aosp (含 .repo, 后续构建跳过 repo sync)"
EOF
    chmod +x "$SRC_DIR/RESTORE.sh"
    (cd "$SRC_DIR" && sha256sum aosp-src."$local_suffix".part-* > aosp-src.sha256)
    echo "源码分卷:"; ls -lh "$SRC_DIR"
fi

# ---------------------------------------------------------------------------
# 3. LFS 推送到 artifacts 分支 (单提交覆盖, 只备份本轮压缩产物, 仓库配额内)
# ---------------------------------------------------------------------------
echo "=== [release/3] Git LFS 推送 artifacts 分支 ==="
ART_BRANCH="${ARTIFACTS_BRANCH:-artifacts}"
ART_DIR="$WS/artifacts_repo"
rm -rf "$ART_DIR" && mkdir -p "$ART_DIR" && cd "$ART_DIR"

URL_NO_PROTO="${CNB_REPO_URL_HTTPS:-https://cnb.cool/$REPO.git}"
URL_NO_PROTO="${URL_NO_PROTO#*://}"
GIT_HOST="${URL_NO_PROTO%%/*}"
REPO_PATH="${URL_NO_PROTO#*/}"; REPO_PATH="${REPO_PATH%.git}"

git init -q -b "$ART_BRANCH"
git config user.email builder@local
git config user.name builder
git remote add origin "https://${CNB_TOKEN_USER_NAME:-cnb}:${TOKEN}@${GIT_HOST}/${REPO_PATH}.git"
git lfs install >/dev/null
git lfs track '*.img' '*.img.xz' '*.dtb' '*.zip' '*.tar*' 'Image' >/dev/null
cp "$STAGE_DIR"/* .
git add -A .
git commit -qm "artifacts($STAGE): $TAG"
git push -q -f origin "$ART_BRANCH"
echo "artifacts 分支已更新: $REPO_PATH@$ART_BRANCH (单提交覆盖)"

# ---------------------------------------------------------------------------
# 4. 发布 Release (产物 + 源码环境) 并执行保留策略
# ---------------------------------------------------------------------------
echo "=== [release/4] 发布产物 Release: $TAG ==="
# 4.1 产物 release 描述 (markdown, 含 sha256)
DESC_FILE=$(mktemp)
python3 - "$STAGE" "$TAG" "$STAGE_DIR" "$DESC_FILE" "$SHORT" <<'PY'
import hashlib, os, sys
stage, tag, sdir, out, short = sys.argv[1:6]
rows = []
for name in sorted(os.listdir(sdir)):
    p = os.path.join(sdir, name)
    if not os.path.isfile(p): continue
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''): h.update(chunk)
    rows.append(f"| `{name}` | {os.path.getsize(p)/1048576:.1f} MiB | `{h.hexdigest()}` |")
body = (
    f"## KC2/K10Plus Android 11 (RK3399) — {stage} 阶段产物\n\n"
    f"- 构建标识: `{tag}`\n- Commit: `{short}`\n\n"
    "| 文件 | 大小 | SHA256 |\n|---|---|---|\n" + "\n".join(rows) +
    "\n\n> kernel 阶段: Image + dtb;  full 阶段: 分区镜像(.xz) + Magisk patched boot。\n"
    "> 大镜像已 sparse+xz 压缩, 刷机前用 `xz -d` 解压。\n"
    "> 源码环境备份见 `kc2-atv11-src-*` 系列 Release (RESTORE.sh 一键还原)。\n"
)
with open(out, 'w') as f: f.write(body)
PY

prune_releases "kc2-atv11-kernel-" "$RELEASES_KEEP"
prune_releases "kc2-atv11-full-" "$RELEASES_KEEP"
upload_dir_as_release "$STAGE_DIR" "$TAG" "$(cat "$DESC_FILE")"
rm -f "$DESC_FILE"

if [ -n "$SRC_TAG" ]; then
    echo "=== [release/5] 发布源码环境 Release: $SRC_TAG ==="
    prune_releases "kc2-atv11-src-" "$RELEASES_KEEP_SRC"
    upload_dir_as_release "$SRC_DIR" "$SRC_TAG" \
        "KC2 AOSP 11 源码环境备份 (含 .repo, 排除 out/)。下载全部分卷 + RESTORE.sh 后执行 \`bash RESTORE.sh\` 还原。Commit: $SHORT"
fi

echo "=== [release] 完成: $CNB_WEB_PROTOCOL://$CNB_WEB_HOST/$REPO/-/releases ==="
