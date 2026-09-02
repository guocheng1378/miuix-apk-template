#!/usr/bin/env bash
# 从 miuix-apk-template 派生一个新 app 工程：一次做完「改包名 + 改应用名 + 改工程名 +
# 改存储 key + 同步 workflow 的 APP_ID 与 assets 镜像」，最后自动跑 preflight。
#
# 为什么要脚本而不是手工 sed：包名同时存在于**文本**和**目录路径**两处，
# 且有一批「不改也能编译、但装上去还是模板身份」的隐性项。实测手工派生时
# 漏掉过 3 处（app_name / rootProject.name / SharedPreferences key），
# 目录移动也写错过一次（多套一层）。这些都是静默失败，preflight 查不出来。
#
# 用法：
#   bash derive-app.sh --package com.foo.bar --name "Foo Bar" --out ../myapp [--template <模板仓库根>]
#
# 说明：
#   - 只改工程文件（app/ shared/ .github/ *.kts *.properties），**不动 skills/ 与 README.md**，
#     那里的旧包名是文档叙述，属于事实记录。
#   - 派生完记得：新仓库要自己配 4 条签名 Secrets（gen-keystore.sh + set-gh-secrets.py），
#     否则 CI 的「Verify APK signature」会主动 exit 1（这是有意的，防装不上的包上 Release 页）。
set -u

die() { echo "错误: $*" >&2; exit 1; }

PKG="" APPNAME="" OUT="" TEMPLATE="" PREFS_KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --package)    PKG="${2:?--package 需要参数}"; shift 2 ;;
    --name)       APPNAME="${2:?--name 需要参数}"; shift 2 ;;
    --out)        OUT="${2:?--out 需要参数}"; shift 2 ;;
    --template)   TEMPLATE="${2:?--template 需要参数}"; shift 2 ;;
    --prefs-key)  PREFS_KEY="${2:?--prefs-key 需要参数}"; shift 2 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *)            die "未知参数: $1（-h 看用法）" ;;
  esac
done

[ -n "$PKG" ]      || die "必须给 --package（新包名，如 com.foo.bar）"
[ -n "$APPNAME" ]  || die "必须给 --name（应用显示名）"
[ -n "$OUT" ]      || die "必须给 --out（输出目录）"

# 包名合法性：至少两段，每段小写字母开头的 Java 标识符，不能是关键字开头
printf '%s' "$PKG" | grep -Eq '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$' \
  || die "包名不合法: $PKG（要求小写点多段，如 com.foo.bar）"

# 默认模板根 = 本脚本所在 skill 的上两级（skills/generate-miuix-app/scripts/ -> 仓库根）
if [ -z "$TEMPLATE" ]; then
  TEMPLATE="$(cd "$(dirname "$0")/../../.." && pwd)"
fi
[ -d "$TEMPLATE/app/src/main/kotlin" ] || die "模板根不对，找不到 app 源码: $TEMPLATE"

SRC_PKG="$(grep -m1 -oE 'applicationId = "[^"]+"' "$TEMPLATE/app/build.gradle.kts" \
           | sed 's/.*"\(.*\)"/\1/')"
[ -n "$SRC_PKG" ] || die "读不出模板的 applicationId（app/build.gradle.kts 格式变了？）"
SRC_PATH="${SRC_PKG//./\/}"
DST_PATH="${PKG//./\/}"

# 存储 key 默认从包名末两段推：com.foo.bar -> foo_bar_prefs
if [ -z "$PREFS_KEY" ]; then
  PREFS_KEY="$(printf '%s' "$PKG" | awk -F. '{print (NF>=2? $(NF-1)"_"$NF : $NF)}' | tr -c 'a-z0-9_' '_')_prefs"
fi

[ -e "$OUT" ] && die "输出目录已存在，拒绝覆盖: $OUT"

echo "模板:   $TEMPLATE"
echo "包名:   $SRC_PKG  ->  $PKG"
echo "应用名: $APPNAME"
echo "存储:   $PREFS_KEY"
echo "输出:   $OUT"
echo

mkdir -p "$(dirname "$OUT")" || die "建不了父目录"
# 排除 .git 与构建产物；skills/ 保留（preflight 的镜像一致性检查要用到镜像文件）
tar -C "$TEMPLATE" \
    --exclude='./.git' --exclude='./build' --exclude='./*/build' \
    --exclude='./.gradle' --exclude='./local.properties' \
    -cf - . | tar -C "$(mkdir -p "$OUT" && echo "$OUT")" -xf - || die "拷贝模板失败"

python3 - "$OUT" "$SRC_PKG" "$PKG" "$SRC_PATH" "$DST_PATH" "$APPNAME" "$PREFS_KEY" <<'PY' || die "派生改写失败"
import os, sys, pathlib

out, src_pkg, dst_pkg, src_path, dst_path, appname, prefs_key = sys.argv[1:8]
root = pathlib.Path(out)

# 1) 文本替换：只碰工程文件。skills/ 与 README.md 里的旧包名是文档叙述，故意不改。
targets = []
for d in ("app", "shared", ".github"):
    p = root / d
    if p.is_dir():
        targets += [f for f in p.rglob("*") if f.is_file()]
for f in (root / "settings.gradle.kts", root / "build.gradle.kts", root / "gradle.properties"):
    if f.is_file():
        targets.append(f)

changed = 0
for f in targets:
    try:
        s = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue                      # 二进制/异常文件跳过，不算漏改
    t = s.replace(src_pkg, dst_pkg)
    if t != s:
        f.write_text(t, encoding="utf-8")
        changed += 1
print(f"  文本改写: {changed} 个文件")

def must_replace(rel, old, new, label):
    """隐性必改项：没命中就报错，不接受静默跳过——静默跳过正是这脚本存在的理由。"""
    f = root / rel
    if not f.is_file():
        raise SystemExit(f"  !! {label}: 文件不存在 {rel}")
    s = f.read_text(encoding="utf-8")
    if old not in s:
        raise SystemExit(f"  !! {label}: 在 {rel} 里没找到 {old!r}（模板结构变了，请人工核对）")
    f.write_text(s.replace(old, new), encoding="utf-8")
    print(f"  {label}: {rel}")

must_replace("app/src/main/res/values/strings.xml",
             ">MIUIX 模板<", f">{appname}<", "应用名")
must_replace("settings.gradle.kts",
             'rootProject.name = "miuix-apk-template"',
             f'rootProject.name = "{appname.lower().replace(" ", "-")}"', "工程名")
must_replace("app/src/main/kotlin/" + src_path + "/AndroidAppPrefs.kt",
             '"miuix_template_prefs"', f'"{prefs_key}"', "存储 key")

# 2) 源码目录随包名移动（文本改完再动目录，避免路径中途失效）
moved = 0
for src_root in ("app/src/main/kotlin", "shared/src/commonMain/kotlin", "shared/src/androidMain/kotlin"):
    base = root / src_root
    if not base.is_dir():
        continue
    for d in [x for x in base.rglob("*") if x.is_dir()]:
        if str(d).replace("\\", "/").endswith(src_path):
            newdir = base / dst_path
            if newdir.exists():
                raise SystemExit(f"  !! 目标目录已存在: {newdir}")
            os.makedirs(newdir.parent, exist_ok=True)
            os.rename(d, newdir)
            moved += 1
            print(f"  移动目录: {d} -> {newdir}")
if moved == 0:
    raise SystemExit(f"  !! 一个源码目录都没移动（找不到以 {src_path} 结尾的包目录）")

# 3) assets 里的 workflow 镜像必须跟着走：preflight 有一条「镜像与 build-apk.yml
#    一致（忽略注释与空行）」的检查，只改仓库那份会立刻撞出 WARN 漂移。
#    这是 skills/ 下唯一要改的文件——其余文档里的旧包名是事实叙述，保持原样。
must_replace("skills/generate-miuix-app/assets/workflow-build-apk.yml",
             src_pkg, dst_pkg, "workflow 镜像")

# 4) 清掉移动后留下的空目录（top/yukonga 这类父链）
for _ in range(6):
    empties = [x for x in root.rglob("*") if x.is_dir() and not any(x.iterdir())]
    if not empties:
        break
    for x in empties:
        x.rmdir()

# 5) 自查：工程里不该再有旧包名（skills/ 与 README 除外）
leftover = []
for f in targets:
    if not f.is_file():
        continue
    try:
        if src_pkg in f.read_text(encoding="utf-8"):
            leftover.append(str(f))
    except (UnicodeDecodeError, OSError):
        pass
if leftover:
    raise SystemExit("  !! 仍有旧包名残留: " + ", ".join(leftover))
print("  残留自查: 干净")
PY
[ $? -eq 0 ] || die "派生未完成"

echo
echo "=== 跑 preflight 自检 ==="
# 注意别写成 `... | tail -8` 后直接读 $?：那拿到的是 tail 的退出码，
# preflight 红了也会被当成通过。这里先把完整输出落文件，再取码、再截尾。
PREFLIGHT_LOG="$(mktemp)"
bash "$OUT/skills/generate-miuix-app/scripts/preflight.sh" "$OUT" > "$PREFLIGHT_LOG" 2>&1
PREFLIGHT=$?
tail -8 "$PREFLIGHT_LOG"
if [ "$PREFLIGHT" -ne 0 ]; then
  echo "!! preflight 未通过（rc=$PREFLIGHT），派生结果不可信，别急着推仓库"
  exit "$PREFLIGHT"
fi

echo
echo "派生完成: $OUT"
echo "下一步："
echo "  1) 配签名 Secrets（否则 CI 会因未签名主动失败）："
echo "       bash $OUT/skills/generate-miuix-app/scripts/gen-keystore.sh --outdir ./ks"
echo "       python3 $OUT/skills/generate-miuix-app/scripts/set-gh-secrets.py \\"
echo "         --repo <owner>/<repo> --from-dir ./ks"
echo "  2) git init 推到新仓库，打 tag 触发构建："
echo "       cd $OUT && git init -b master && git add -A && git commit -m 'init' && \\"
echo "         git remote add origin <url> && git push -u origin master && \\"
echo "         git tag v0.1.0 && git push origin v0.1.0"
