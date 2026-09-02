#!/usr/bin/env bash
# MIUIX 模板仓库的静态自检：把「已经核实过的坑」变成可执行的 grep 检查。
#
# 为什么用 grep 而不是跑 gradle：本机通常没有 JDK/Android SDK，构建类问题只能等 CI；
# 但这几条硬前提（compileSdk 37、PKCS12、AGP9 不叠加 kotlin.android、secrets 出现在
# step if: 里……）全部能在源码文本层面判定，且违反任一条就是必然失败——提前 5 秒查出来
# 比等一轮 CI 便宜得多。
#
# 已知局限：这是文本级启发式。它能证明「硬约束没被违反」，不能证明「能编译」；
# 依赖注释与字符串的写法仍可能误判，所以匹配前一律先剥掉注释（见 strip_comments）。
#
# 用法：bash preflight.sh [仓库根目录]     （默认当前目录）
# 退出码：任一 FAIL 为 1，全 PASS 为 0。WARN 不影响退出码。
#
# 为什么不开 pipefail：grep -q 命中后立即退出并关闭管道，上游的 sed/awk/find 会收到
# SIGPIPE 而以 141 结束；开了 pipefail 之后整条管道被判为「失败」，于是 `if producer
# | grep -q PAT` 在命中时反而走进 else 分支——检查被静默跳过，比报错更糟（本版曾在
# workflow 的 assembleRelease 门控上真实复现：命中行在文件第 51 行，sed 还没写完就被
# 掐断，整组检查凭空消失）。因此这里只 set -u，并且一律把文本先读进变量、再用
# here-string 喂给 grep，不留下「生产者 | grep -q」这种写法。
set -u

ROOT="${1:-.}"
[ -d "$ROOT" ] || { echo "错误: 目录不存在: $ROOT" >&2; exit 2; }

PASS=0; FAIL=0; WARN=0

ok()   { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
bad()  { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
warn() { printf '  WARN  %s\n' "$1"; WARN=$((WARN+1)); [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

# 剥掉注释后输出到 stdout。这一步不是洁癖：模板文件里大量注释写的是「不要写 X」
# （例如 app/build.gradle.kts 注释里就出现 org.jetbrains.kotlin.android 这个字符串），
# 直接 grep 源码会把劝诫当成事实，产生假阳性——本脚本第一版就在这一条上翻过车。
strip_comments() {
  case "$1" in
    *.kts|*.kt)   sed -e 's://.*::' -e 's:/\*[^*]*\*/::g' "$1" ;;
    *.properties) sed -e 's:[[:space:]]*#.*::' "$1" ;;
    *.yml|*.yaml) sed -e 's:[[:space:]]*#.*::' "$1" ;;
    *.xml)        sed -e 's:<!--.*-->::g' "$1" ;;   # 只处理单行 XML 注释，跨行的漏网
    *)            cat "$1" ;;
  esac
}

# 剥注释 + 匹配，一次把文本读进变量再喂 here-string（见文件头 pipefail 说明）。
cgrep() {
  local file="$1" pat="$2" body
  [ -n "$file" ] && [ -f "$file" ] || return 1
  body="$(strip_comments "$file")"
  grep -Eq -- "$pat" <<<"$body"
}

# 在 root 下按文件名找第一个匹配，排除构建产物与 VCS 目录
find_one() {
  find "$ROOT" \( -name build -o -name .git -o -name .gradle -o -name node_modules \) -prune -o \
       -name "$1" -print 2>/dev/null | head -n 1
}
# 目录名都是 build.gradle.kts，靠父目录名区分 app / shared
find_module_bg() {
  local want="$1" f
  for f in $(find "$ROOT" \( -name build -o -name .git -o -name .gradle \) -prune -o \
                 -name 'build.gradle.kts' -print 2>/dev/null); do
    case "$(basename "$(dirname "$f")")" in
      "$want") echo "$f"; return 0 ;;
    esac
  done
  return 1
}
APP_BG="$(find_module_bg app)"
SHARED_BG="$(find_module_bg shared)"
SETTINGS="$(find_one 'settings.gradle.kts')"
GRPROPS="$(find_one 'gradle.properties')"
MANIFEST="$(find_one 'AndroidManifest.xml')"
WORKFLOW_DIR="$ROOT/.github/workflows"

echo "== MIUIX 模板静态自检：$ROOT =="
echo

# ---- 1. 工程骨架 ----
echo "[工程结构]"
[ -n "$SETTINGS" ] && ok "settings.gradle.kts 存在" || bad "缺 settings.gradle.kts"
[ -n "$APP_BG" ] && ok "app/build.gradle.kts 存在" || bad "缺 app/build.gradle.kts"
[ -n "$SHARED_BG" ] && ok "shared/build.gradle.kts 存在" || bad "缺 shared/build.gradle.kts"
if [ -f "$ROOT/build.gradle.kts" ]; then
  warn "根目录存在 build.gradle.kts" "本模板的设计是没有根构建文件，配置全在 settings + 两个模块里"
else
  ok "无根 build.gradle.kts（符合模板设计）"
fi

# ---- 2. compileSdk 37（miuix AAR 的 minCompileSdk 实测为 37）----
echo
echo "[compileSdk / minSdk]"
for f in "$APP_BG" "$SHARED_BG"; do
  [ -z "$f" ] && continue
  m="$(basename "$(dirname "$f")")/build.gradle.kts"
  if cgrep "$f" 'compileSdk[[:space:]]*=[[:space:]]*37'; then
    ok "$m: compileSdk = 37"
  else
    bad "$m: compileSdk 不是 37" \
        "miuix 0.9.4-rc01 的 AAR 声明 minCompileSdk=37，低于 37 构建直接失败"
  fi
done
if cgrep "$APP_BG" 'targetSdk[[:space:]]*=[[:space:]]*37'; then
  ok "targetSdk = 37"
else
  warn "未显式设 targetSdk = 37" "targetSdk 31+ 才强制 android:exported，模板里是显式写的"
fi

# ---- 3. AGP 9 的插件组合 ----
echo
echo "[Gradle 插件]"
if [ -n "$APP_BG" ]; then
  if cgrep "$APP_BG" 'org\.jetbrains\.kotlin\.android'; then
    bad "app 模块应用了 org.jetbrains.kotlin.android" \
        "AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报 Remove the 'org.jetbrains.kotlin.android' plugin"
  else
    ok "app 模块未叠加 kotlin.android（AGP 9 正确形态）"
  fi
  cgrep "$APP_BG" 'com\.android\.application' \
    && ok "app 用 com.android.application" || bad "app 缺 com.android.application"
fi
if [ -n "$SHARED_BG" ]; then
  if cgrep "$SHARED_BG" 'com\.android\.kotlin\.multiplatform\.library'; then
    ok "shared 用 com.android.kotlin.multiplatform.library"
  else
    bad "shared 未用 KMP 库专用插件" \
        "用 com.android.library 会与 KMP 扩展名冲突（AGP 9）"
  fi
  cgrep "$SHARED_BG" 'androidResources[[:space:]]*\{' \
    && ok "shared 开了 androidResources" \
    || bad "shared 缺 androidResources { enable = true }" \
           "新插件默认关闭资源处理，缺则 res/ 不生效"
fi

# ---- 4. Coil 3 的 source set 归属 ----
echo
echo "[依赖]"
if [ -n "$SHARED_BG" ]; then
  if cgrep "$SHARED_BG" 'coil-network-okhttp'; then
    # 取 androidMain 块之后的内容判断 okhttp 是否落在其中（同样先剥注释）
    shared_body="$(strip_comments "$SHARED_BG")"
    if awk '/androidMain/,0' <<<"$shared_body" | grep -Eq 'coil-network-okhttp'; then
      ok "coil-network-okhttp 在 androidMain"
    else
      bad "coil-network-okhttp 不在 androidMain" \
          "commonMain 没有该变体，放错位置会依赖解析失败"
    fi
  else
    bad "缺 coil-network-okhttp" "网络图必需（配合 Manifest 的 INTERNET 权限）"
  fi
  cgrep "$SHARED_BG" 'io\.coil-kt\.coil3:coil-compose' \
    && ok "coil-compose 已声明" || bad "缺 io.coil-kt.coil3:coil-compose"
  cgrep "$SHARED_BG" 'miuix-blur' \
    && ok "miuix-blur 已声明" || warn "未声明 miuix-blur" "液态玻璃底栏依赖它"
fi

# ---- 5. gradle.properties 残留项 ----
echo
echo "[gradle.properties]"
if [ -n "$GRPROPS" ]; then
  if cgrep "$GRPROPS" 'android\.newDsl'; then
    bad "gradle.properties 残留 android.newDsl" \
        "shared 迁移到 KMP 新 DSL 后该行已删除，留着会误导（最终只有 5 行）"
  else
    ok "无 android.newDsl 残留"
  fi
  cgrep "$GRPROPS" 'android\.useAndroidX=true' \
    && ok "android.useAndroidX=true" || bad "缺 android.useAndroidX=true"
fi

# ---- 6. Manifest ----
echo
echo "[AndroidManifest]"
if [ -n "$MANIFEST" ]; then
  cgrep "$MANIFEST" 'android\.permission\.INTERNET' \
    && ok "INTERNET 权限（Coil 网络图必需）" || bad "缺 INTERNET 权限"
  cgrep "$MANIFEST" 'android:exported="true"' \
    && ok "android:exported=\"true\"" || bad "缺 android:exported=\"true\"" \
        "targetSdk 31+ 缺则安装后无法启动"
  cgrep "$MANIFEST" 'tools:overrideLibrary="top\.yukonga\.miuix\.kmp\.blur"' \
    && ok "overrideLibrary 放行 miuix-blur" \
    || warn "缺 tools:overrideLibrary miuix-blur" \
       "blur 的 AAR 实测 minSdkVersion=33；工程 minSdk 24 时不加会构建失败"
else
  bad "找不到 AndroidManifest.xml"
fi

# ---- 7. 签名配置 ----
echo
echo "[签名]"
if cgrep "$APP_BG" 'signingConfig'; then
  cgrep "$APP_BG" 'storeType[[:space:]]*=[[:space:]]*"PKCS12"' \
    && ok "signingConfig 显式 storeType = \"PKCS12\"" \
    || bad "signingConfig 缺 storeType = \"PKCS12\"" \
           "openssl 产的是 PKCS12，AGP 按默认 JKS 读会失败"
else
  warn "app 里没有 signingConfig" "没有它 CI 只会产出 app-release-unsigned.apk（装不上）"
fi
if [ -f "$ROOT/.gitignore" ]; then
  miss=""
  for pat in '*.p12' '*.jks' '*.keystore' 'local.properties'; do
    grep -qF -- "$pat" "$ROOT/.gitignore" || miss="$miss $pat"
  done
  [ -z "$miss" ] && ok ".gitignore 覆盖 keystore 与 local.properties" \
                 || bad ".gitignore 缺:$miss" "私钥/口令一旦提交，public 仓库等于公开"
else
  bad "缺 .gitignore"
fi

# ---- 8. workflow ----
# 检查按用途门控：不是每个 workflow 都构建 APK，对 dependency-review 这类
# 只读 workflow 要求「签名校验步骤」只会制造噪音。
echo
echo "[GitHub Actions]"
if [ -d "$WORKFLOW_DIR" ]; then
  ymls="$(find "$WORKFLOW_DIR" \( -name '*.yml' -o -name '*.yaml' \) -print 2>/dev/null)"
  [ -n "$ymls" ] && ok "workflows 目录有 yml" || bad "workflows 目录为空"
  for y in $ymls; do
    n="$(basename "$y")"
    body="$(strip_comments "$y")"
    # 全通用：secrets 出现在 if: 里对任何 workflow 都是致命的
    if grep -qE '^[[:space:]]*if:.*secrets\.' <<<"$body"; then
      bad "$n: step 级 if: 里引用了 secrets.*" \
          "secrets 不在 if 上下文里，会导致 workflow 解析成 0 个 job；判断请写进 shell step 内部"
    else
      ok "$n: if: 里没有 secrets.*"
    fi

    if grep -qE 'action-gh-release|softprops' <<<"$body"; then
      grep -Eq 'contents:[[:space:]]*write' "$y" \
        && ok "$n: 创建 Release，且已授予 contents: write" \
        || bad "$n: 创建 Release 但缺 permissions contents: write" \
             "缺省 GITHUB_TOKEN 只有 read，会 403 Resource not accessible by integration"
    fi

    if grep -qE 'assembleRelease|assemble-release' <<<"$body"; then
      if grep -qF './gradlew' <<<"$body"; then
        warn "$n: 用了 ./gradlew" "仓库未提交 wrapper jar，CI 应直接用 gradle（由 setup-gradle 提供）"
      else
        ok "$n: 构建 APK，且不依赖未提交的 wrapper"
      fi
      grep -qE 'apksigner|unsigned' <<<"$body" \
        && ok "$n: 有签名校验兜底步骤" \
        || warn "$n: 构建 release 但没有签名校验步骤" \
           "建议：产物名含 unsigned 就 exit 1，再 apksigner verify --print-certs"
    fi
  done
else
  bad "缺 .github/workflows 目录" "无 JDK 环境下 CI 是唯一能真正构建/签名的地方"
fi

# ---- 9. 运行时降级分支 ----
echo
echo "[降级分支]"
kt_files="$(find "$ROOT" \( -name .git -o -name build -o -name .gradle \) -prune -o -name '*.kt' -print 2>/dev/null)"
if [ -n "$kt_files" ]; then
  hits="$(xargs grep -lE 'isRuntimeShaderSupported' 2>/dev/null <<<"$kt_files" || true)"
  if [ -n "$hits" ]; then
    ok "有 isRuntimeShaderSupported() 判定"
  else
    bad "代码里没有 isRuntimeShaderSupported()" \
        "blur 需 RuntimeShader（Android 12+）；工程 minSdk 24 能装到低版本机器上，缺降级分支就是运行期崩溃"
  fi
else
  warn "找不到任何 .kt 文件" "仓库还没生成代码，跳过降级分支检查"
fi

# ---- 10. assets 镜像漂移 ----
# assets/workflow-build-apk.yml 是仓库那份 workflow 的镜像，只用于新项目起点。
# 仓库里的 .github/workflows/build-apk.yml 才是权威；镜像一旦落后，就会教人把
# 旧版本抄回去——漂移的模板比没有模板更糟。本次重构中它就真的落后过一次
# （仓库把 actions/download-artifact 从 v7 升到 v8，镜像没跟上）。
echo
echo "[模板镜像]"
MIRROR="$(find_one 'workflow-build-apk.yml')"
LIVE="$WORKFLOW_DIR/build-apk.yml"
if [ -n "$MIRROR" ] && [ -f "$LIVE" ]; then
  drift="$(diff <(strip_comments "$MIRROR" | grep -vE '^[[:space:]]*$') \
               <(strip_comments "$LIVE" | grep -vE '^[[:space:]]*$') | head -8)"
  if [ -z "$drift" ]; then
    ok "assets 的 workflow 镜像与仓库权威版一致（忽略注释与空行）"
  else
    warn "assets 的 workflow 镜像与 .github/workflows/build-apk.yml 漂移" \
         "以仓库那份为准并同步镜像。前几处差异: $(echo "$drift" | tr '\n' ' | ')"
  fi
else
  echo "  ----    没有镜像可比（派生仓库一般不带 skills/…/assets/），跳过"
fi

echo
echo "== 结果：PASS=$PASS FAIL=$FAIL WARN=$WARN =="
if [ "$FAIL" -gt 0 ]; then
  echo "存在 $FAIL 项硬失败，先修掉再交付（对应说明见 references/pitfalls.md）。"
  exit 1
fi
echo "静态检查通过。注意：grep 级检查不能证明能编译——"
echo "构建、二进制、运行时三类检测仍需 gradle/SDK 或 GitHub Actions 实跑。"
