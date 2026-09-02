#!/usr/bin/env bash
# 在没有 java / keytool 的机器上，用 openssl 产出 Android Release 签名用的 PKCS12 keystore。
#
# 为什么走 PKCS12 而不是 JKS：keytool 属于 JDK，很多 CI 之外的环境（含本机）没有 JDK，
# 但几乎都有 openssl。代价是 app/build.gradle.kts 的 signingConfig 必须显式
# storeType = "PKCS12"，否则 AGP 按默认 JKS 读取会失败。
#
# 产物：cert.pem key.pem release.p12 password.txt，并把 base64 -w0 的 keystore 打到 stdout 尾部，
# 可直接作为 GitHub Secret SIGNING_KEY 的值。
#
# 用法：
#   bash gen-keystore.sh [--alias NAME] [--subject DN] [--days N] [--outdir DIR] [--password PASS]
set -euo pipefail

ALIAS="release"
SUBJECT="/C=CN/O=unknown/CN=android-release"
DAYS=10950
OUTDIR="./keystore"
PASSWORD=""

die() { echo "错误: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --alias)    ALIAS="${2:?--alias 需要参数}"; shift 2 ;;
    --subject)  SUBJECT="${2:?--subject 需要参数}"; shift 2 ;;
    --days)     DAYS="${2:?--days 需要参数}"; shift 2 ;;
    --outdir)   OUTDIR="${2:?--outdir 需要参数}"; shift 2 ;;
    --password) PASSWORD="${2:?--password 需要参数}"; shift 2 ;;
    -h|--help)  sed -n '2,15p' "$0"; exit 0 ;;
    *)          die "未知参数: $1（-h 看用法）" ;;
  esac
done

command -v openssl >/dev/null 2>&1 \
  || die "找不到 openssl。本脚本的唯一硬依赖就是它——有 JDK 的话改用 keytool -genkeypair 更省事"

# 不传口令时随机生成：签名口令写死成弱默认值等于没签名（keystore 一旦泄露无法吊销）
if [ -z "$PASSWORD" ]; then
  PASSWORD="$(openssl rand -hex 16)"
  echo "已随机生成口令并写入 $OUTDIR/password.txt" >&2
fi

mkdir -p "$OUTDIR"

# 自签证书：Android 只要求签名密钥有效，不要求 CA 链，所以 req -x509 自签即可用于上架
openssl req -x509 -newkey rsa:2048 -sha256 -days "$DAYS" -nodes \
  -keyout "$OUTDIR/key.pem" -out "$OUTDIR/cert.pem" \
  -subj "$SUBJECT" 2>/dev/null \
  || die "openssl req 失败（检查 --subject 格式：/C=.. /O=.. /CN=..）"

# -name 决定 alias，必须与 KEY_ALIAS 一致，否则 AGP 找不到条目
openssl pkcs12 -export -inkey "$OUTDIR/key.pem" -in "$OUTDIR/cert.pem" \
  -out "$OUTDIR/release.p12" -name "$ALIAS" \
  -passout "pass:$PASSWORD" \
  || die "openssl pkcs12 -export 失败"

printf '%s\n' "$PASSWORD" > "$OUTDIR/password.txt"
chmod 600 "$OUTDIR/password.txt" "$OUTDIR/key.pem" "$OUTDIR/release.p12"
printf '%s\n' "$ALIAS" > "$OUTDIR/alias.txt"

# 回读验证：产完就 self-check，别等到 CI 上才发现文件是坏的
openssl pkcs12 -in "$OUTDIR/release.p12" -info -noout -passin "pass:$PASSWORD" >/dev/null 2>&1 \
  || die "生成的 release.p12 无法用该口令打开，口令与 alias 可能不匹配"

cat <<EOF

已生成（$OUTDIR/）：
  release.p12      → base64 后作为 SIGNING_KEY
  password.txt     → KEYSTORE_PASSWORD 与 KEY_PASSWORD（openssl 路径下两者相同）
  alias.txt        → KEY_ALIAS = $ALIAS
  cert.pem/key.pem → 原始材料，请异地备份

下一步：
  python3 set-gh-secrets.py --repo <owner>/<repo> --from-dir "$OUTDIR"

提醒：
  1. app/build.gradle.kts 的 signingConfig 必须写 storeType = "PKCS12"
  2. 仓库是 public 时绝不要把 release.p12 当 workflow artifact 上传
  3. keystore 与口令丢了，同一 applicationId 再也无法覆盖升级到已装用户机上
EOF

echo "----- SIGNING_KEY 的值（base64 -w0，单行） -----"
base64 -w0 "$OUTDIR/release.p12"
echo
