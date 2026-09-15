#!/usr/bin/env bash
# =============================================================================
# AOSP 源码环境 -> WebDAV 备份 (CNB 对象存储额度吃紧时的替代通道)
#
# 用法:
#   bash upload_src_to_webdav.sh                 # 打包 + 上传 (默认全树, 排除 out/.ccache)
#   PACK_WHAT=repo bash upload_src_to_webdav.sh   # 只备份 .repo (体积约减半; 还原时用本地对象离线出工作树)
#   UPLOAD_ONLY=1 bash upload_src_to_webdav.sh    # 跳过打包, 只上传/续传已有分卷
#   DRY_RUN=1 bash upload_src_to_webdav.sh        # 只打包不上传 (验证流程与体积)
#
# 凭证 (任选其一, 优先级从高到低):
#   export WEBDAV_USER=<账号> WEBDAV_PASS=<应用密码>
#   WEBDAV_CREDS=<文件>   指定其他凭证文件 (多端点时用)
#   $WS/.secrets/webdav   第一行=账号, 第二行=应用密码 (也支持单行 user:pass; 已在 .gitignore)
#
# 远端结果 ($WEBDAV_URL/$WEBDAV_DIR/$TAG/):
#   aosp-src.tar.zst.part-aa...   分卷 (默认 1GiB/卷)
#   aosp-src.sha256               分卷 SHA256 清单
#   RESTORE.sh                    还原脚本
#   MANIFEST.txt                  体积/时间/分卷数记录
#
# 还原: 把整个目录下载到本地同一目录, 执行 bash RESTORE.sh [目标目录]
#   注意 123pan 的 GET 会 302 跳到 CDN 签名地址, 命令行下载必须带 -L, 否则存下来的是 HTML:
#     curl -sSL -u "$WEBDAV_USER:$WEBDAV_PASS" -O "$REMOTE_DIR/aosp-src.tar.zst.part-aa"   # 逐个分卷
#     (或浏览器直接打开该目录逐个下载; 全部落到同一目录后再跑 RESTORE.sh)
#
# 说明:
#   - 分卷在远端已存在且大小一致时自动跳过 -> 天然断点续传, 重跑本脚本即可
#   - 123pan 实测上传 ~4 MB/s, 即 1GiB/卷 约 4 分钟; 每卷上传后打印 卷序/进度/速度/预计剩余
#   - 只走 WebDAV, 不占用 CNB 仓库存储/对象存储额度
#
# 已验证端点 (2026-09-15 实测):
#   123pan  WEBDAV_URL=https://webdav.123pan.cn/webdav   上传 ~4.1 MB/s
#           (下载: GET 会 302 跳 CDN 签名地址, curl 必须带 -L)
#   NAS     WEBDAV_URL=https://nas.ai0128.com:5006        上传 ~1.1 MB/s  (5005 为 HTTP 版)
#           WEBDAV_DIR=cnb-space/cnb-upload/<子目录>       (WebDAV 路径按共享文件夹写, 不带 /volume1)
#           注意: 5001 端口是 DSM 网页, /dav/ 不是 WebDAV (PROPFIND 一律 405)
# =============================================================================
set -euo pipefail

WS="${WORKSPACE:-/workspace}"
SRC="${SRC_DIR:-$WS/aosp}"
SRC_PARENT="$(cd "$(dirname "$SRC")" && pwd)"
SRC_NAME="$(basename "$SRC")"

WEBDAV_URL="${WEBDAV_URL:-https://webdav.123pan.cn/webdav}"
WEBDAV_URL="${WEBDAV_URL%/}"
WEBDAV_DIR="${WEBDAV_DIR:-kc2-aosp-src}"
SHORT="${CNB_COMMIT_SHORT:-manual}"
TAG="${TAG:-$(date +%Y%m%d)-$SHORT}"
SPLIT_BYTES="${SPLIT_BYTES:-1073741824}"      # 1GiB/卷 (WebDAV 单文件越稳, 断点粒度越细)
PACK_WHAT="${PACK_WHAT:-all}"                 # all=工作树+.repo | repo=仅 .repo
WORK="${WORK:-$WS/webdav_upload}"             # 本地暂存目录 (分卷落地处)
DRY_RUN="${DRY_RUN:-0}"
UPLOAD_ONLY="${UPLOAD_ONLY:-0}"
FORCE="${FORCE:-0}"                           # 暂存空间不足时仍继续

[ -d "$SRC" ] || { echo "ERROR: 源码目录不存在: $SRC"; exit 1; }
case "$PACK_WHAT" in all|repo) ;; *) echo "ERROR: PACK_WHAT 只能是 all 或 repo"; exit 1 ;; esac
for t in curl tar split sha256sum df; do
    command -v "$t" >/dev/null || { echo "ERROR: 缺少命令: $t"; exit 1; }
done

# ---------------------------------------------------------------------------
# 0. 凭证
# ---------------------------------------------------------------------------
WEBDAV_USER="${WEBDAV_USER:-}"
WEBDAV_PASS="${WEBDAV_PASS:-}"
if [ -z "$WEBDAV_USER" ] || [ -z "$WEBDAV_PASS" ]; then
    for f in "${WEBDAV_CREDS:-}" "$WS/.secrets/webdav" "$HOME/.webdav"; do
        [ -n "$f" ] && [ -s "$f" ] || continue
        l1=$(sed -n 1p "$f" | tr -d '\r')
        l2=$(sed -n 2p "$f" | tr -d '\r\n')
        if [ -z "$l2" ] && [[ "$l1" == *:* ]]; then
            WEBDAV_USER="${WEBDAV_USER:-${l1%%:*}}"
            WEBDAV_PASS="${WEBDAV_PASS:-${l1#*:}}"
        else
            WEBDAV_USER="${WEBDAV_USER:-$l1}"
            WEBDAV_PASS="${WEBDAV_PASS:-$l2}"
        fi
        break
    done
fi
if [ -z "$WEBDAV_USER" ] || [ -z "$WEBDAV_PASS" ]; then
    cat >&2 <<'EOF'
ERROR: 未找到 WebDAV 凭证。任选其一:
  1. export WEBDAV_USER=<账号> WEBDAV_PASS=<应用密码>
  2. printf '%s\n%s\n' <账号> <应用密码> > /workspace/.secrets/webdav && chmod 600 /workspace/.secrets/webdav
  3. WEBDAV_CREDS=/path/to/creds   (多端点: 例如 .secrets/webdav-nas)
EOF
    exit 1
fi

REMOTE_BASE="$WEBDAV_URL/$WEBDAV_DIR"
REMOTE_DIR="$REMOTE_BASE/$TAG"
AUTH=(-u "$WEBDAV_USER:$WEBDAV_PASS")

# 远端文件大小 (PROPFIND, 取不到返回 0)
remote_size() {
    curl -sS --max-time 30 "${AUTH[@]}" -X PROPFIND -H 'Depth: 0' "$1" 2>/dev/null \
        | grep -oE 'getcontentlength>[0-9]+' | grep -oE '[0-9]+' | head -1 || true
}

mkcol() {
    local code
    code=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "${AUTH[@]}" -X MKCOL "$1/")
    case "$code" in
        201|200|204|301|302|405) echo "  目录就绪: $1 ($code)" ;;
        *) echo "ERROR: 无法创建远端目录 $1 (HTTP $code)"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# 1. 自检: 连通性 + 远端目录 + 暂存空间
# ---------------------------------------------------------------------------
echo "=== [webdav/1] 自检 ==="
code=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "${AUTH[@]}" -X PROPFIND -H 'Depth: 0' "$WEBDAV_URL/")
[ "$code" = "207" ] || { echo "ERROR: WebDAV 不可用 (HTTP $code): $WEBDAV_URL"; exit 1; }
echo "  WebDAV 连通: $WEBDAV_URL (207)"
hint=$(curl -sS --max-time 30 "${AUTH[@]}" -X PROPFIND -H 'Depth: 0' -H 'Content-Type: application/xml' \
    --data-binary '<?xml version="1.0"?><D:propfind xmlns:D="DAV:"><D:prop><D:quota-available-bytes/><D:quota-used-bytes/></D:prop></D:propfind>' \
    "$WEBDAV_URL/" 2>/dev/null | grep -oE 'quota-(available|used)-bytes>[0-9]+' | head -2 || true)
[ -n "$hint" ] && echo "  远端配额: $(echo "$hint" | tr '\n' ' ')" || echo "  远端配额: 服务端未提供 (跳过)"
mkcol "$REMOTE_BASE"
mkcol "$REMOTE_DIR"

mkdir -p "$WORK"
if [ "$UPLOAD_ONLY" != "1" ]; then
    tree_kb=$(du -sk "$SRC" | awk '{print $1}')
    need_kb=$(( tree_kb * 55 / 100 ))          # zstd -2 后经验值约原始体积的 55%
    avail_kb=$(df -Pk "$WORK" | awk 'NR==2{print $4}')
    echo "  源码体积: $(numfmt --to=iec $((tree_kb*1024))) | 暂存需要约 $(numfmt --to=iec $((need_kb*1024))) | 可用 $(numfmt --to=iec $((avail_kb*1024)))"
    if [ "$avail_kb" -lt "$need_kb" ] && [ "$FORCE" != "1" ]; then
        echo "ERROR: 暂存空间可能不足 (估算需 $((need_kb/1048576))GiB)。清理 $WORK 或设置 FORCE=1 继续。"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. 打包 (tar + zstd, 流式 split; 不落中间大文件)
# ---------------------------------------------------------------------------
SUFFIX="tar.zst"
if [ "$UPLOAD_ONLY" != "1" ]; then
    echo "=== [webdav/2] 打包 -> $WORK ==="
    rm -rf "$WORK"; mkdir -p "$WORK"
    if command -v zstd >/dev/null; then COMPRESS="zstd -T0 -2"; SUFFIX="tar.zst"
    elif command -v pigz >/dev/null; then COMPRESS="pigz -1"; SUFFIX="tar.gz"
    else COMPRESS="gzip -1"; SUFFIX="tar.gz"; fi
    echo "  压缩: $COMPRESS | 分卷: $(numfmt --to=iec "$SPLIT_BYTES")/卷 | 内容: $SRC_NAME ($PACK_WHAT)"

    case "$PACK_WHAT" in
        all)  TAR_PATH="$SRC_NAME";                EXCLUDES=(--exclude="$SRC_NAME/out" --exclude="$SRC_NAME/.ccache") ;;
        repo) TAR_PATH="$SRC_NAME/.repo";          EXCLUDES=() ;;
    esac
    EXCLUDES+=(--exclude="$SRC_NAME/.repo/repo.tmp")

    T0=$(date +%s)
    (cd "$SRC_PARENT" && tar --use-compress-program="$COMPRESS" "${EXCLUDES[@]}" -cf - "$TAR_PATH") \
        | split -b "$SPLIT_BYTES" - "$WORK/aosp-src.$SUFFIX.part-"
    echo "  打包完成, 用时 $(( ($(date +%s) - T0) / 60 )) 分钟"

    # 校验清单 + 还原脚本 + 记录
    (cd "$WORK" && sha256sum aosp-src."$SUFFIX".part-* > aosp-src.sha256)
    {
        echo "#!/usr/bin/env bash"
        echo "# KC2/K10Plus AOSP 11 源码环境还原 (下载本目录全部文件后执行)"
        echo "# 用法: bash RESTORE.sh [目标目录, 默认 /workspace]"
        echo "set -euo pipefail"
        echo 'DEST="${1:-/workspace}"'
        echo "SUFFIX=\"$SUFFIX\""
        echo 'echo "== 校验分卷 SHA256 =="'
        echo 'sha256sum -c aosp-src.sha256'
        echo 'echo "== 合并分卷 =="'
        echo 'cat aosp-src.$SUFFIX.part-* > "$DEST/aosp-src.$SUFFIX"'
        echo 'echo "== 解压到 $DEST =="'
        echo 'case "$SUFFIX" in'
        echo '  tar.zst) tar --use-compress-program="zstd -T0" -xf "$DEST/aosp-src.$SUFFIX" -C "$DEST" ;;'
        echo '  *)       tar -xf "$DEST/aosp-src.$SUFFIX" -C "$DEST" ;;'
        echo 'esac'
        echo 'rm -f "$DEST/aosp-src.$SUFFIX"'
        if [ "$PACK_WHAT" = "repo" ]; then
            echo 'echo "== 用本地对象离线检出工作树 (不联网) =="'
            echo "cd \"\$DEST/$SRC_NAME\" && repo sync -l -c -j8"
        fi
        echo "echo \"完成: \$DEST/$SRC_NAME\""
    } > "$WORK/RESTORE.sh"
    chmod +x "$WORK/RESTORE.sh"

    N_PARTS=$(find "$WORK" -maxdepth 1 -name "aosp-src.$SUFFIX.part-*" | wc -l)
    PART_BYTES=$(du -sb "$WORK" | awk '{print $1}')
    {
        echo "KC2/K10Plus AOSP 11 源码环境备份"
        echo "打包时间  : $(date -Is)"
        echo "内容      : $SRC_NAME (PACK_WHAT=$PACK_WHAT)"
        echo "原始体积  : $(du -sh "$SRC" | awk '{print $1}')"
        echo "压缩      : $COMPRESS"
        echo "分卷      : $N_PARTS 卷 x $(numfmt --to=iec "$SPLIT_BYTES") (合计 $(numfmt --to=iec "$PART_BYTES"))"
        echo "远端位置  : $REMOTE_DIR"
        echo "还原      : 下载整目录后 bash RESTORE.sh [目标目录]"
    } > "$WORK/MANIFEST.txt"
    cat "$WORK/MANIFEST.txt"
else
    echo "=== [webdav/2] UPLOAD_ONLY=1, 跳过打包 ==="
    ls -1 "$WORK" >/dev/null 2>&1 || { echo "ERROR: 暂存目录为空: $WORK"; exit 1; }
fi

# ---------------------------------------------------------------------------
# 3. 上传 (分卷按序; 远端同大小则跳过)
# ---------------------------------------------------------------------------
echo "=== [webdav/3] 上传到 $REMOTE_DIR ==="
upload_file() {   # $1=本地文件 $2=远端 URL $3=显示名
    local f="$1" url="$2" label="$3" sz rs ok=0 i
    sz=$(stat -c%s "$f")
    rs=$(remote_size "$url"); rs="${rs:-0}"
    if [ "$rs" = "$sz" ]; then
        echo "  跳过 (远端已存在同大小): $label"; return 0
    fi
    for i in 1 2 3; do
        if curl -sS --fail --connect-timeout 30 --retry 2 --retry-delay 10 --no-progress-meter \
             "${AUTH[@]}" -T "$f" "$url" -o /dev/null \
             -w '  OK: '"$label"' %{size_upload}B %{speed_upload}B/s %{time_total}s\n'; then
            ok=1; break
        fi
        echo "  上传失败, 重试 $i/3: $label"; sleep $((i * 15))
    done
    [ "$ok" = 1 ] || { echo "ERROR: 上传失败: $label"; return 1; }
    rs=$(remote_size "$url"); rs="${rs:-0}"
    [ "$rs" = "$sz" ] || { echo "ERROR: 远端大小不符 ($rs != $sz): $label"; return 1; }
}

PARTS=( "$WORK"/aosp-src.*.part-* )
TOTAL_BYTES=0
for f in "${PARTS[@]}"; do TOTAL_BYTES=$(( TOTAL_BYTES + $(stat -c%s "$f") )); done
N=${#PARTS[@]}
UP_T0=$(date +%s); UP_BYTES=0; idx=0

for f in "${PARTS[@]}"; do
    idx=$(( idx + 1 ))
    name=$(basename "$f")
    sz=$(stat -c%s "$f")
    upload_file "$f" "$REMOTE_DIR/$name" "$name"
    UP_BYTES=$(( UP_BYTES + sz ))
    el=$(( $(date +%s) - UP_T0 ))
    if [ "$el" -gt 0 ]; then
        rate=$(( UP_BYTES / el ))
        [ "$rate" -gt 0 ] && eta=$(( (TOTAL_BYTES - UP_BYTES) / rate / 60 )) || eta=0
        printf '  [上传进度] %d/%d 卷 | %d/%d MiB | %d MiB/s | 预计剩余 %d 分钟\n' \
            "$idx" "$N" "$(( UP_BYTES / 1048576 ))" "$(( TOTAL_BYTES / 1048576 ))" \
            "$(( rate / 1048576 ))" "$eta"
    fi
done

for extra in aosp-src.sha256 RESTORE.sh MANIFEST.txt; do
    [ -s "$WORK/$extra" ] && upload_file "$WORK/$extra" "$REMOTE_DIR/$extra" "$extra"
done

# ---------------------------------------------------------------------------
# 4. 完成
# ---------------------------------------------------------------------------
echo
echo "======================================================================="
echo " 源码环境已备份到 WebDAV:"
echo "   $REMOTE_DIR"
echo " 文件: $N 个分卷 + aosp-src.sha256 + RESTORE.sh + MANIFEST.txt"
echo " 还原: 下载整个目录到本地同一目录, 然后:"
echo "   bash RESTORE.sh /workspace"
echo " (PACK_WHAT=$PACK_WHAT${UPLOAD_ONLY:+, UPLOAD_ONLY=1})"
echo "======================================================================="
