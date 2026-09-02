#!/usr/bin/env bash
# MIUIX 模板仓库的静态自检：把「已经核实过的坑」变成可执行的 grep 检查。
#
# 为什么用 grep 而不是跑 gradle：本机通常没有 JDK/Android SDK，构建类问题只能等 CI；
# 但这几条硬前提（compileSdk 37、PKCS12、AGP9 不叠加 kotlin.android、secrets 出现在
# step if: 里……）全部能在源码文本层面判定，且违反任一条就是必然失败——提前 5 秒查出来
# 比等一轮 CI 便宜得多。
#
# 已知局限：这是文本级启发式。它能证明「硬约束没被违反」，不能证明「能编译」；
# 依赖注释与字符串的写法仍可能误判，所以匹配前一律先剥掉注释（见 strip_code）。
#
# 关于「静默消失」：本脚本的上一版有三类检查会在出问题的那一刻同时消失——
# (1) 整节包在 `if [ -n "$某文件" ]` 里，文件一缺，整节连 FAIL 都不记；
# (2) 节内计数为零时不报错，读者只看到 PASS 数变少，看不出少了一节；
# (3) 生产者 | grep -q 在 pipefail 下被 SIGPIPE 判为失败，命中反而走 else。
# 这一版针对三者分别加了 need_file（缺文件即 FAIL）、start_section（节内 0 项即
# FAIL）、以及全局不开 pipefail + here-string。三条都是变异测试真实打出来的洞。
#
# 用法：bash preflight.sh [仓库根目录]     （默认当前目录）
# 退出码：任一 FAIL 为 1，全 PASS 为 0，WARN 不影响退出码；
#         参数给的目录不存在时直接 exit 2（连一节都没跑，别误读成「通过」）。
#
# 为什么不开 pipefail：grep -q 命中后立即退出并关闭管道，上游的 sed/awk/find 会收到
# SIGPIPE 而以 141 结束；开了 pipefail 之后整条管道被判为「失败」，于是 `if producer
# | grep -q PAT` 在命中时反而走进 else 分支——检查被静默跳过，比报错更糟（本版曾在
# workflow 的 assembleRelease 门控上真实复现：命中行在文件第 51 行，sed 还没写完就被
# 掐断，整组检查凭空消失）。因此这里只 set -u。凡是能把文本先读进变量、再用 here-string
# 喂给 grep 的地方一律这么写（见 cgrep / scan_kt）；确需管道的地方（any_kt 的 head）
# 上游只可能是 SIGPIPE，而判定读的是下游 grep 的结果，不受影响。
set -u

ROOT="${1:-.}"
[ -d "$ROOT" ] || { echo "错误: 目录不存在: $ROOT" >&2; exit 2; }

PASS=0; FAIL=0; WARN=0
SECT=""; SEC=0

ok()   { PASS=$((PASS+1)); SEC=$((SEC+1)); printf '  PASS  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
bad()  { FAIL=$((FAIL+1)); SEC=$((SEC+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
warn() { WARN=$((WARN+1)); SEC=$((SEC+1)); printf '  WARN  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }
info() { SEC=$((SEC+1)); printf '  ----  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; return 0; }

# 每节都必须真正跑到。上一节一项检查都没执行（多半是它依赖的文件没找到，
# 而那个缺失又被 need_file 之外的路径绕过了）就是脚本自身的 bug，按 FAIL 报。
close_section() {
  if [ -n "$SECT" ] && [ "$SEC" -eq 0 ]; then
    FAIL=$((FAIL+1)); printf '  FAIL  检查节「%s」实际执行了 0 项检查（整节被静默跳过）\n' "$SECT"
  fi
  SEC=0
}
start_section() {
  close_section
  SECT="$1"
  printf '\n[%s]\n' "$1"
}

# ---- 注释剥离 ------------------------------------------------------------------
# 这一步不是洁癖：模板文件里大量注释写的是「不要写 X」（例如 app/build.gradle.kts
# 注释里就出现 org.jetbrains.kotlin.android 这个字符串，pitfalls 文档里连写了
# PreferenceCategory），直接 grep 源码会把劝诫当成事实，产生假阳性。
#
# 旧的 sed 's:/\*[^*]*\*/::g' 有两个致命问题：(1) `[^*]*` 遇到 KDoc 开头的
# `/**` 立刻停住，所以 `/** ... */` 整块剥不掉；(2) 它会把 maven("https://…") 从
# `//` 处截断，制造出 `maven("https:` 这种半行。下面这段 awk 是字符串感知的状态机：
# 只在字符串外识别 // 与 /* */，因此 URL、正则字面量、KDoc 里的引号都不会误伤。
STRIP_AWK='BEGIN{inblk=0}{
  line=$0; out=""; i=1; n=length(line)
  while(i<=n){
    c=substr(line,i,1); c2=substr(line,i,2)
    if(inblk){ if(c2=="*/"){inblk=0;i+=2;continue} i++; continue }
    if(c2=="//"){ break }
    if(c2=="/*"){ inblk=1;i+=2;continue }
    if(c=="\"" || c=="\x27"){
      q=c; out=out c; i++
      while(i<=n){
        cc=substr(line,i,1); out=out cc
        if(cc=="\\"){ i++; if(i<=n){ out=out substr(line,i,1); i++ }; continue }
        i++; if(cc==q) break
      }
      continue
    }
    out=out c; i++
  }
  print out
}'

# 剥掉 <file> 的注释，输出到 stdout（保留行号，便于报 file:line）
strip_code() {
  case "$1" in
    *.kts|*.kt)   awk "$STRIP_AWK" "$1" 2>/dev/null ;;
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
  body="$(strip_code "$file")"
  grep -Eq -- "$pat" <<<"$body"
}

# 跨多个 .kt 搜索（已剥注释），输出 file:line:内容。$1=正则，其余为文件列表。
scan_kt() {
  local pat="$1"; shift
  local f body
  for f in "$@"; do
    [ -f "$f" ] || continue
    body="$(strip_code "$f")"
    grep -nE -- "$pat" <<<"$body" | sed "s|^|$f:|"
  done
}
# 命中即返回 0（不打印）
any_kt() { [ -n "$(scan_kt "$1" "${@:2}" | head -n 1)" ]; }

# 检查「某函数调用的直接实参里出现了某个标识符」，跨行也算。
# 为什么不用行内正则：`Scaffold[[:space:]]*\([^)]*scrollBehavior` 只能在一行内匹配，
# 多行写法（Scaffold( 换行再写 scrollBehavior = ...）直接漏过；而把它改成「整篇压平再匹配」
# 又会假阳性——模板里合法的 TopAppBar(scrollBehavior = ...) 恰恰嵌在 Scaffold 的 topBar
# lambda 里。所以按圆括号深度判定：只有深度正好 1（即 Scaffold 自己的实参列表）里的
# 内容才参与匹配，嵌套调用的参数一律不算。
# 局限：不识别字符串里的括号；Kotlin 三引号原始字符串里的 // 仍会被当成行注释截断。
scan_direct_arg() {  # $1=函数名 $2=参数/标识符 其余=文件
  local fn="$1" name="$2" f
  shift 2
  for f in "$@"; do
    [ -f "$f" ] || continue
    strip_code "$f" | awk -v FN="$f" -v fun="$fn" -v arg="$name" '
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          if (!match(lines[i], "(^|[^A-Za-z0-9_])" fun "[ \t]*\\(")) continue
          depth = 0; started = 0; buf = ""; closed = 0
          for (j = i; j <= NR && j < i + 200; j++) {
            t = lines[j]
            if (j == i) t = substr(t, RSTART + RLENGTH - 1)
            n = length(t)
            for (k = 1; k <= n; k++) {
              c = substr(t, k, 1)
              if (c == "(") { depth++; if (depth == 1) started = 1; continue }
              if (c == ")") { if (depth == 1) { closed = 1; break }; depth--; continue }
              if (started && depth == 1) buf = buf c
            }
            if (closed) break
            if (started) buf = buf " "
          }
          if (match(buf, "(^|[^A-Za-z0-9_])" arg "[^A-Za-z0-9_]"))
            print FN ":" i ": " fun "(...) 的直接实参里出现 " arg
        }
      }'
  done
}

# 取出 <file> 中第一个匹配 $2 的「xxx {」块的大括号内部（含嵌套，按计数配对）。
# 为什么不用 awk '/androidMain/,0'：那是「从 androidMain 那行一直到文件结尾」，
# 后面 iosMain.dependencies 里的依赖会被算进 androidMain 头上——变异测试里把
# coil-network-okhttp 整块挪进 iosMain 后，检查照样报「在 androidMain」。
# 局限：按大括号计数，不识别字符串里的 { }；build.gradle.kts 里没有这种写法。
block_of() {  # $1=file $2=块起始行正则（匹配到含 { 的那一行）
  local f="$1" re="$2" body
  [ -n "$f" ] && [ -f "$f" ] || return 1
  body="$(strip_code "$f")"
  awk -v re="$re" '
    !inblk { if ($0 ~ re) inblk=1; else next }
    {
      n=length($0)
      for (i=1;i<=n;i++) {
        c=substr($0,i,1)
        if (c=="{") { depth++; if (depth==1) continue }
        else if (c=="}") { if (depth==1) exit; depth-- }
        if (depth>=1) printf "%s", c
      }
      if (depth>=1) printf "\n"
    }
  ' <<<"$body"
}

# ---- 文件定位 ------------------------------------------------------------------
# 需要某文件才能做的检查，先过 need_file：文件缺失本身就是 FAIL，
# 绝不允许「文件没了 → 整节没了 → 看起来只是少了几条 PASS」。
NEED_SEEN=""
need_file() {
  if [ -z "${1:-}" ] || [ ! -f "$1" ]; then
    case " $NEED_SEEN " in *"|$2|"*)
      info "本节依赖的${2}缺失" "已在前面报过 FAIL"
      return 1 ;;
    esac
    NEED_SEEN="$NEED_SEEN|$2|"
    bad "找不到 ${2}" "依赖它的检查全部无法执行——这一条修好前，本节其余结论都不可信"
    return 1
  fi
  return 0
}

# 在 root 下按文件名找第一个匹配，排除构建产物与 VCS 目录
find_one() {
  find "$ROOT" \( -name build -o -name .git -o -name .gradle -o -name node_modules \) -prune -o \
       -name "$1" -print 2>/dev/null | head -n 1
}
# AndroidManifest 可能有好几份（main/debug/androidTest…），find 的返回顺序不保证，
# 抓到 debug 那份去查 INTERNET/exported 会得到「作用域随机」的结论。固定优先 src/main。
find_manifest() {
  local all main
  all="$(find "$ROOT" \( -name build -o -name .git -o -name .gradle -o -name node_modules \) -prune -o \
             -name 'AndroidManifest.xml' -print 2>/dev/null)"
  [ -n "$all" ] || return 0
  main="$(grep -m1 '/src/main/.*AndroidManifest\.xml$' <<<"$all")"
  [ -n "$main" ] || main="$(head -n 1 <<<"$all")"
  printf '%s\n' "$main"
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
MANIFEST="$(find_manifest)"
WRAPPER="$(find_one 'gradle-wrapper.properties')"
WORKFLOW_DIR="$ROOT/.github/workflows"

# 全部 .kt（含 skill 自带的 assets 镜像——那是要抄进新项目的真代码，误用检查该覆盖它）
KT_ALL=()
while IFS= read -r -d '' f; do KT_ALL+=("$f"); done < <(
  find "$ROOT" \( -name build -o -name .git -o -name .gradle -o -name node_modules \) -prune -o \
       -name '*.kt' -print0 2>/dev/null)
# 参与「包名↔目录」校验的源码：排除 skills/ 镜像（它的目录结构是 assets 布局，不适用规则）
KT_SRC=()
for f in ${KT_ALL[@]+"${KT_ALL[@]}"}; do
  case "$f" in */skills/*) continue ;; esac
  KT_SRC+=("$f")
done

echo "== MIUIX 模板静态自检：$ROOT =="

# ---- 1. 工程骨架 ----
start_section "工程结构"
need_file "$SETTINGS" "settings.gradle.kts" && ok "settings.gradle.kts 存在"
need_file "$APP_BG" "app/build.gradle.kts" && ok "app/build.gradle.kts 存在"
need_file "$SHARED_BG" "shared/build.gradle.kts" && ok "shared/build.gradle.kts 存在"
need_file "$GRPROPS" "gradle.properties" && ok "gradle.properties 存在"
need_file "$MANIFEST" "AndroidManifest.xml" && ok "AndroidManifest.xml 存在"
if [ -f "$ROOT/build.gradle.kts" ]; then
  warn "根目录存在 build.gradle.kts" "本模板的设计是没有根构建文件，配置全在 settings + 两个模块里"
else
  ok "无根 build.gradle.kts（符合模板设计）"
fi
if [ "${#KT_SRC[@]}" -eq 0 ]; then
  bad "仓库里没有任何 .kt 源码" \
      "骨架齐了但代码是空的——后面「导航/主题/液态玻璃/API 误用」四节全部无从校验，这种仓库不可能构建出可用 APK"
else
  ok "含 ${#KT_SRC[@]} 个 .kt 源文件"
fi
if [ -n "$WRAPPER" ]; then
  ok "gradle/wrapper/gradle-wrapper.properties 存在"
else
  warn "缺 gradle-wrapper.properties" "CI 用 setup-gradle 提供的 gradle 也能构建，但本地 ./gradlew 会不可用"
fi

# ---- 2. compileSdk 37（miuix AAR 的 minCompileSdk 实测为 37）----
start_section "compileSdk / minSdk"
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
if cgrep "$APP_BG" 'minSdk[[:space:]]*=[[:space:]]*24'; then
  ok "minSdk = 24"
else
  warn "minSdk 不是 24" "模板取 24 覆盖绝大多数设备；改高会缩小装机面，改低要确认 miuix 支持"
fi
if cgrep "$APP_BG" 'targetSdk[[:space:]]*=[[:space:]]*37'; then
  ok "targetSdk = 37"
else
  warn "未显式设 targetSdk = 37" "targetSdk 31+ 才强制 android:exported，模板里是显式写的"
fi

# ---- 3. AGP 9 的插件组合 ----
start_section "Gradle 插件"
if need_file "$APP_BG" "app/build.gradle.kts"; then
  if cgrep "$APP_BG" 'org\.jetbrains\.kotlin\.android'; then
    bad "app 模块应用了 org.jetbrains.kotlin.android" \
        "AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报 Remove the 'org.jetbrains.kotlin.android' plugin"
  else
    ok "app 模块未叠加 kotlin.android（AGP 9 正确形态）"
  fi
  if cgrep "$APP_BG" 'com\.android\.application'; then
    ok "app 用 com.android.application"
  else
    bad "app 缺 com.android.application"
  fi
fi
if need_file "$SHARED_BG" "shared/build.gradle.kts"; then
  if cgrep "$SHARED_BG" 'com\.android\.kotlin\.multiplatform\.library'; then
    ok "shared 用 com.android.kotlin.multiplatform.library"
  else
    bad "shared 未用 KMP 库专用插件" \
        "用 com.android.library 会与 KMP 扩展名冲突（AGP 9）"
  fi
  if cgrep "$SHARED_BG" 'androidResources[[:space:]]*\{'; then
    ok "shared 开了 androidResources"
  else
    bad "shared 缺 androidResources { enable = true }" \
        "新插件默认关闭资源处理，缺则 res/ 不生效"
  fi
fi

# ---- 4. 依赖与 source set 归属 ----
start_section "依赖"
if need_file "$SHARED_BG" "shared/build.gradle.kts"; then
  if cgrep "$SHARED_BG" 'coil-network-okhttp'; then
    # 只在 androidMain.dependencies { ... } 的块体内判定归属（见 block_of）
    am_deps="$(block_of "$SHARED_BG" 'androidMain[^{]*dependencies' || true)"
    if grep -Eq 'coil-network-okhttp' <<<"$am_deps"; then
      ok "coil-network-okhttp 在 androidMain"
    else
      bad "coil-network-okhttp 不在 androidMain" \
          "commonMain 没有该变体，放错位置会依赖解析失败"
    fi
  else
    bad "缺 coil-network-okhttp" "网络图必需（配合 Manifest 的 INTERNET 权限）"
  fi
  if cgrep "$SHARED_BG" 'io\.coil-kt\.coil3:coil-compose'; then
    ok "coil-compose 已声明"
  else
    bad "缺 io.coil-kt.coil3:coil-compose"
  fi
  if cgrep "$SHARED_BG" 'miuix-blur'; then
    ok "miuix-blur 已声明"
  else
    warn "未声明 miuix-blur" "液态玻璃底栏依赖它"
  fi
  if cgrep "$SHARED_BG" 'miuix-nav'; then
    ok "miuix-nav 已声明"
  else
    warn "未声明 miuix-nav" "多页面导航（NavDisplay + NavKey）依赖它"
  fi
  if cgrep "$SHARED_BG" 'kotlinx-serialization-core'; then
    ok "kotlinx-serialization-core 已声明"
  else
    bad "缺 kotlinx-serialization-core" \
        "NavKey 要求路由 @Serializable，缺序列化运行时 NavKey 无法编译"
  fi
fi
if need_file "$APP_BG" "app/build.gradle.kts"; then
  if cgrep "$APP_BG" 'project\(":shared"\)'; then
    ok "app 依赖 :shared"
  else
    bad "app 未 implementation(project(\":shared\"))" "代码都在 shared 里，缺这条 app 是个空壳"
  fi
  if cgrep "$APP_BG" 'androidx\.activity:activity-compose'; then
    ok "activity-compose 已声明"
  else
    bad "缺 androidx.activity:activity-compose" "setContent 需要它"
  fi
fi
# 用 miuix 就不要混 material3：两套组件的视觉/手势语言不同，且 miuix 已自带等价物。
# 这里匹配「任何出现」而不是只匹配 import 行：写成全限定名
# （androidx.compose.material3.Text(...)）同样引到了 material3，早先只 grep import
# 时这种写法直接漏过（变异测试 B06）。注释里的反例名已由 strip_code 剥掉。
m3_hits="$(scan_kt 'androidx\.compose\.material3' ${KT_ALL[@]+"${KT_ALL[@]}"})"
if [ -z "$m3_hits" ]; then
  ok "没有 androidx.compose.material3 残留"
else
  bad "存在 material3 引用（$(printf '%s\n' "$m3_hits" | wc -l) 处）" \
      "$(printf '%s\n' "$m3_hits" | head -3)
组件请改用 top.yukonga.miuix.kmp.basic / .component / .theme 下的等价物（import 或直接写全限定名都算）"
fi

# ---- 5. gradle.properties 残留项 ----
start_section "gradle.properties"
if need_file "$GRPROPS" "gradle.properties"; then
  if cgrep "$GRPROPS" 'android\.newDsl'; then
    bad "gradle.properties 残留 android.newDsl" \
        "shared 迁移到 KMP 新 DSL 后该行已删除，留着会误导（最终只有 5 行）"
  else
    ok "无 android.newDsl 残留"
  fi
  if cgrep "$GRPROPS" 'android\.useAndroidX=true'; then
    ok "android.useAndroidX=true"
  else
    bad "缺 android.useAndroidX=true" "AndroidX 依赖（activity-compose、compose）解析不到"
  fi
  if cgrep "$GRPROPS" 'android\.nonTransitiveRClass=true'; then
    ok "android.nonTransitiveRClass=true"
  else
    warn "未设 android.nonTransitiveRClass=true" "不设也能构建，但 R 类会传递合并，模板里是显式开的"
  fi
fi

# ---- 6. 仓库解析（settings.gradle.kts）----
# 这一节管的是「依赖从哪来」。CI 上最常见的两种失败——插件解析不到、
# miuix/compose 的坐标解析不到——根因都在这里，而不是在 build.gradle.kts 里。
start_section "仓库与解析"
if need_file "$SETTINGS" "settings.gradle.kts"; then
  sbody="$(strip_code "$SETTINGS")"
  if grep -Eq 'pluginManagement[[:space:]]*\{' <<<"$sbody"; then
    ok "有 pluginManagement 块"
  else
    bad "settings 缺 pluginManagement" \
        "没有它，build.gradle.kts 里的 id(\"...\") version \"...\" 无处解析，配置阶段直接报 plugin not found"
  fi
  if grep -Eq 'dependencyResolutionManagement[[:space:]]*\{' <<<"$sbody"; then
    ok "有 dependencyResolutionManagement 块"
  else
    bad "settings 缺 dependencyResolutionManagement" \
        "本模板不在模块里写 repositories，仓库列表集中在这里"
  fi
  if grep -Eq 'repositoriesMode[[:space:]]*\.set[[:space:]]*\(' <<<"$sbody"; then
    ok "设了 repositoriesMode"
  else
    bad "缺 repositoriesMode" \
        "不设的话模块里可以偷偷追加仓库（模板注释就写过这个教训），复现性被破坏"
  fi
  for r in 'google\(\)' 'mavenCentral\(\)'; do
    if grep -Eq -- "$r" <<<"$sbody"; then
      ok "仓库含 $(tr -d '\\\\' <<<"$r")"
    else
      bad "settings 缺仓库 $(tr -d '\\\\' <<<"$r")" "AGP/Compose 走 google()，Kotlin 插件与 kotlinx 走 mavenCentral()"
    fi
  done
  if grep -Eq 'gradlePluginPortal\(\)' <<<"$sbody"; then
    ok "仓库含 gradlePluginPortal()（pluginManagement 侧）"
  else
    warn "缺 gradlePluginPortal()" "roborazzi 之类的第三方插件通常靠它解析"
  fi
  if grep -Eq 'maven\.pkg\.jetbrains\.space' <<<"$sbody"; then
    ok "仓库含 JetBrains Compose dev maven"
  else
    bad "缺 https://maven.pkg.jetbrains.space/public/p/compose/dev" \
        "miuix 依赖的 compose 快照/预发布构件在这里"
  fi
  if grep -Eq 'rootProject\.name[[:space:]]*=' <<<"$sbody"; then
    ok "设了 rootProject.name"
  else
    bad "缺 rootProject.name"
  fi
  if grep -Eq 'include\("[^"]*:app"' <<<"$sbody"; then
    ok "include(\":app\")"
  else
    bad "settings 没有 include(\":app\")" "模块没被包含时 :app:assembleRelease 报 task not found"
  fi
  if grep -Eq 'include\([^)]*:shared' <<<"$sbody"; then
    ok "include(\":shared\")"
  else
    bad "settings 没有 include(\":shared\")" "app 里的 project(\":shared\") 会解析不到"
  fi
fi

# ---- 7. 版本矩阵 ----
# 只报偏离，不因为「比模板新/旧一个小版本」就 FAIL：这些版本能互相组合的空间很宽，
# 真正会 FAIL 的是上面 compileSdk 那一类硬前提。偏离提示以 CI 实跑为准。
start_section "版本矩阵"
ver_of() {  # $1=file $2=插件/坐标关键字（ERE，已转义）-> 版本号
  local f="$1" key="$2" body
  [ -n "$f" ] && [ -f "$f" ] || return 1
  body="$(strip_code "$f")"
  grep -oE -- "${key}[^[:cntrl:]]*" <<<"$body" | head -n 1 \
    | grep -oE '[0-9]+[0-9A-Za-z._-]*' | tail -n 1
}
check_ver() {  # $1=名称 $2=实际 $3=期望 $4=来源
  if [ -z "$2" ]; then
    warn "$1 版本读不出来" "来源 $4 里没匹配到；期望 $3"
  elif [ "$2" = "$3" ]; then
    ok "$1 = $2"
  else
    warn "$1 = $2（模板用 $3）" "版本矩阵偏离不一定坏，但请确认 CI 实跑过；说明见 references/pitfalls.md"
  fi
}
agp="$(ver_of "$APP_BG" 'id\("com\.android\.application"\)')"
agp_shared="$(ver_of "$SHARED_BG" 'id\("com\.android\.kotlin\.multiplatform\.library"\)')"
kmp="$(ver_of "$SHARED_BG" 'id\("org\.jetbrains\.kotlin\.multiplatform"\)')"
compose_p="$(ver_of "$SHARED_BG" 'id\("org\.jetbrains\.compose"\)')"
miuix_v="$(ver_of "$SHARED_BG" 'top\.yukonga\.miuix\.kmp:miuix-ui')"
coil_v="$(ver_of "$SHARED_BG" 'io\.coil-kt\.coil3:coil-compose')"
ser_v="$(ver_of "$SHARED_BG" 'org\.jetbrains\.kotlinx:kotlinx-serialization-core')"
act_v="$(ver_of "$APP_BG" 'androidx\.activity:activity-compose')"
gradle_v=""
if [ -n "$WRAPPER" ]; then
  # -bin.zip 与 -all.zip 都是合法发行包，早先只认 -bin\.zip：改成 -all 之后
  # gradle_v 变成空串，整条「AGP 9 需要 Gradle 9.x」硬约束静默降级成一条 WARN。
  gradle_v="$(grep -oE 'gradle-[0-9][0-9.]*(-[A-Za-z]+)?-(bin|all)\.zip' "$WRAPPER" \
                | sed -E 's/^gradle-//; s/-(bin|all)\.zip$//' | head -n 1)"
fi

check_ver "AGP(app)" "$agp" "9.3.2" "app/build.gradle.kts"
if [ -n "$agp" ] && [ -n "$agp_shared" ]; then
  if [ "$agp" = "$agp_shared" ]; then
    ok "AGP 两模块同号（$agp）"
  else
    bad "AGP 两模块不同号：app=$agp shared=$agp_shared" "同号才不会出现两个 android 扩展抢注 DSL"
  fi
fi
check_ver "Kotlin" "$kmp" "2.4.10" "shared/build.gradle.kts"
check_ver "org.jetbrains.compose" "$compose_p" "1.12.0" "shared/build.gradle.kts"
check_ver "miuix" "$miuix_v" "0.9.4-rc01" "shared/build.gradle.kts"
check_ver "Coil" "$coil_v" "3.6.1" "shared/build.gradle.kts"
check_ver "kotlinx-serialization-core" "$ser_v" "1.11.0" "shared/build.gradle.kts"
check_ver "activity-compose" "$act_v" "1.13.0" "app/build.gradle.kts"
if [ -z "$gradle_v" ]; then
  if [ -n "$WRAPPER" ]; then
    bad "读不出 $WRAPPER 里的 Gradle 版本" \
        "distributionUrl 必须写成 https\\://services.gradle.org/distributions/gradle-<版本>-bin.zip（或 -all.zip）；「AGP 9 需要 Gradle 9.x」这条硬约束在版本读不出来时等于没检查，所以按 FAIL 处理而不是 WARN"
  else
    warn "没有 gradle-wrapper.properties，无法核对 Gradle 版本" "CI 用 setup-gradle 提供的 gradle 时靠 workflow 里的版本参数，见「工程结构」节"
  fi
else
  case "$gradle_v" in
    9.*) ok "Gradle wrapper = $gradle_v" ;;
    *)   bad "Gradle wrapper = $gradle_v" "AGP 9.x 需要 Gradle 9.x，低版本在配置阶段就报 minimum supported version" ;;
  esac
fi
# compose 编译器插件必须存在，且与 Kotlin 同号（它是按 Kotlin 版本编译的）。
# 模板现状是 app 与 shared 的 plugins {} 里各声明一次，所以「任一处声明」即算存在，
# 两处都没有才是真的缺插件。早先的写法是 `if [ -n "$comp_ver" ] && [ != ] then bad else ok`
# —— 版本号读不出来（= 插件被删掉）时正好落进 else，报成「与 Kotlin 同号」。
comp_app="$(ver_of "$APP_BG" 'id\("org\.jetbrains\.kotlin\.plugin\.compose"\)')"
comp_shared="$(ver_of "$SHARED_BG" 'id\("org\.jetbrains\.kotlin\.plugin\.compose"\)')"
if [ -z "$comp_app" ] && [ -z "$comp_shared" ]; then
  bad "app 与 shared 都没有声明 org.jetbrains.kotlin.plugin.compose" \
      "Kotlin 2.x 起 compose 编译器已从 kotlin 插件里拆出，必须单独声明，否则所有 @Composable 在编译期报「this function is deprecated / cannot be called」一类的插件缺失错误"
else
  if [ -n "$comp_app" ] && [ -n "$comp_shared" ] && [ "$comp_app" != "$comp_shared" ]; then
    bad "compose 编译器插件两模块不同号：app=$comp_app shared=$comp_shared" "同一构建里只能有一个 compose 编译器版本"
  else
    ok "compose 编译器插件已声明（app=${comp_app:-无} shared=${comp_shared:-无}）"
  fi
  comp_ver="${comp_app:-$comp_shared}"
  if [ -z "$kmp" ]; then
    bad "读不到 Kotlin 版本，无法核对 compose 编译器插件是否同号" \
        "shared 的 id(\"org.jetbrains.kotlin.multiplatform\") version 没解析到；compose 插件必须与 Kotlin 严格同号"
  elif [ "$comp_ver" != "$kmp" ]; then
    bad "compose 编译器插件 $comp_ver 与 Kotlin $kmp 不同号" "KSP/compose 插件与 Kotlin 版本错配是经典的编译期报错"
  else
    ok "compose 编译器插件与 Kotlin 同号（$comp_ver）"
  fi
fi

# ---- 8. Manifest ----
start_section "AndroidManifest"
if need_file "$MANIFEST" "AndroidManifest.xml"; then
  if cgrep "$MANIFEST" 'android\.permission\.INTERNET'; then
    ok "INTERNET 权限（Coil 网络图必需）"
  else
    bad "缺 INTERNET 权限"
  fi
  if cgrep "$MANIFEST" 'android:exported="true"'; then
    ok "android:exported=\"true\""
  else
    bad "缺 android:exported=\"true\"" "targetSdk 31+ 缺则安装后无法启动"
  fi
  if cgrep "$MANIFEST" 'android\.intent\.action\.MAIN'; then
    ok "有 LAUNCHER intent-filter"
  else
    bad "Manifest 里没有 MAIN/LAUNCHER intent-filter" "装得上但桌面上没有图标"
  fi
  if cgrep "$MANIFEST" 'tools:overrideLibrary="top\.yukonga\.miuix\.kmp\.blur"'; then
    ok "overrideLibrary 放行 miuix-blur"
  else
    bad "缺 tools:overrideLibrary miuix-blur" \
        "blur 的 AAR 实测 minSdkVersion=33；工程 minSdk 24 时不加会构建失败（Manifest merger 直接报错）"
  fi
  # 主题资源引用：@style/Xxx 必须在 res/values* 里真的存在，否则安装即 Resources$NotFoundException
  resdir="$(dirname "$MANIFEST")/res"
  theme_ref="$(sed -n 's/.*android:theme="@style\/\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)"
  if [ -z "$theme_ref" ]; then
    info "跳过 @style 校验" "Manifest 没有 android:theme=\"@style/...\" 引用，无需校验"
  elif [ ! -d "$resdir" ]; then
    bad "Manifest 引用 @style/$theme_ref，但 $resdir 不存在" \
        "res 目录整个没了，aapt 链接阶段必失败；请确认资源放在 app/src/main/res（或 manifest 同级的 res/）"
  else
    # 整名匹配，且用 -F 固定串：早先写的是 ${theme_ref%%.*}（把 Theme.Miuix 截成 Theme），
    # 于是任何 Theme.* 都能顶替，改名成 Theme.Zzz 也照样 PASS。
    # 注意 -exec 的 {} 这里是 values* 目录本身，必须再走 -type f 取文件，
    # 否则 grep 只会报 "Is a directory" 而永远查不到命中（第一版就栽在这里）。
    theme_hit="$(find "$resdir" -type d -name 'values*' -print 2>/dev/null \
                   | while IFS= read -r vd; do
                       grep -rlF --include='*.xml' "name=\"${theme_ref}\"" "$vd" 2>/dev/null
                     done | head -n 1)"
    if [ -n "$theme_hit" ]; then
      ok "android:theme=@style/$theme_ref 在 ${theme_hit#"$ROOT"/} 里有定义"
    else
      bad "Manifest 引用 @style/$theme_ref，但 res/values* 里找不到同名 <style>" "安装后启动即 Resources\$NotFoundException"
    fi
    if grep -qrE 'name="ic_launcher"' "$resdir" 2>/dev/null || ls "$resdir"/mipmap*/ic_launcher.* >/dev/null 2>&1; then
      ok "ic_launcher 资源存在"
    else
      bad "Manifest 引用 @mipmap/ic_launcher 但没有该资源" "缺图标 aapt 直接链接失败"
    fi
  fi
fi

# ---- 9. 包名 ↔ 目录 ↔ namespace ↔ applicationId ----
# 这四者不一致时，报错点往往离根因很远（R 类找不到、Manifest 校验失败、
# 运行期 ClassNotFoundException），所以在这里一次对齐。
start_section "包名一致性"
ns_app=""; aid=""
if need_file "$APP_BG" "app/build.gradle.kts"; then
  ns_app="$(strip_code "$APP_BG" | sed -n 's/.*namespace[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  aid="$(strip_code "$APP_BG" | sed -n 's/.*applicationId[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "$ns_app" ]; then
    bad "app/build.gradle.kts 没有 namespace"
  else
    ok "app namespace = $ns_app"
  fi
  if [ -z "$aid" ]; then
    bad "app/build.gradle.kts 没有 applicationId" "打包时无法确定包名，assembleRelease 直接失败"
  elif [ "$aid" = "$ns_app" ]; then
    ok "applicationId 与 namespace 一致（$aid）"
  else
    bad "applicationId=$aid 与 namespace=$ns_app 不一致" \
        "R 类生成在 namespace 包下、代码 import 也按 namespace；两者不同时要么编译期找不到 R，要么运行期按 applicationId 找类失败"
  fi
fi
if need_file "$SHARED_BG" "shared/build.gradle.kts"; then
  ns_shared="$(strip_code "$SHARED_BG" | sed -n 's/.*namespace[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "$ns_shared" ]; then
    bad "shared/build.gradle.kts 没有 namespace"
  elif [ -n "$ns_app" ]; then
    case "$ns_shared" in
      "$ns_app"|"$ns_app".*) ok "shared namespace=$ns_shared（在 app namespace 之下）" ;;
      *) bad "shared namespace=$ns_shared 不以 app namespace=$ns_app 为前缀" \
            "两套包名树分叉后，import 与 R 类极易写错，模板约定 shared 挂在 app 包名之下" ;;
    esac
  fi
fi
if [ "${#KT_SRC[@]}" -gt 0 ]; then
  pkg_bad=0; pkg_checked=0
  for f in "${KT_SRC[@]}"; do
    rel="${f#"$ROOT"/}"
    # 只认 .../src/<sourceSet>/kotlin/<pkg>/X.kt 这种布局；不符合的跳过
    sub="$(sed -E 's|^.*/src/[^/]+/kotlin/||' <<<"$rel")"
    [ "$sub" = "$rel" ] && continue          # 不在 kotlin 目录下，规则不适用
    case "$sub" in */*) ;; *) continue ;; esac   # 直接放 kotlin/ 下，没有包目录可比
    dir_pkg="$(dirname "$sub" | tr '/' '.')"
    decl="$(strip_code "$f" | sed -nE 's/^[[:space:]]*package[[:space:]]+([a-zA-Z0-9_.]+).*/\1/p' | head -n 1)"
    pkg_checked=$((pkg_checked+1))
    if [ "$decl" != "$dir_pkg" ]; then
      pkg_bad=$((pkg_bad+1))
      [ "$pkg_bad" -le 5 ] && bad "$rel: package=$decl 与目录要求 $dir_pkg 不符" \
        "Kotlin 允许不一致，但 namespace/R/import 三处约定都按目录走；一旦分叉，跨模块引用会莫名找不到符号"
    fi
  done
  if [ "$pkg_bad" -eq 0 ] && [ "$pkg_checked" -gt 0 ]; then
    ok "$pkg_checked 个源文件的 package 声明与目录、namespace 全部对齐"
  elif [ "$pkg_checked" -eq 0 ]; then
    warn "没有任何源文件落在 src/<sourceSet>/kotlin/ 下" "包名↔目录一致性无法校验，请确认源集布局"
  fi
fi

# ---- 10. 导航与页面接线 ----
start_section "导航与页面接线"
if [ "${#KT_SRC[@]}" -gt 0 ]; then
  if any_kt 'NavDisplay[[:space:]]*\(' "${KT_SRC[@]}"; then
    ok "有 NavDisplay"
  else
    bad "代码里没有 NavDisplay" \
        "miuix-nav 的导航入口就是它；缺了等于多页面没接起来，navController 白建（Route 定义了也没人去 entry）"
  fi
  if any_kt 'rememberNavController' "${KT_SRC[@]}"; then
    ok "有 rememberNavController"
  else
    bad "代码里没有 rememberNavController" "NavDisplay 的 navController 参数需要它"
  fi
  if any_kt 'sealed[[:space:]]+(interface|class)[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*NavKey' "${KT_SRC[@]}"; then
    ok "路由类型是 sealed ... : NavKey"
  else
    bad "没有 sealed interface/class X : NavKey 的路由定义" \
        "miuix-nav 的 key 类型是 NavKey，用 NavHost 那套字符串路由名不兼容"
  fi
  n_entry="$(scan_kt '\bentry[[:space:]]*<' "${KT_SRC[@]}" | wc -l)"
  n_ser="$(scan_kt '@Serializable' "${KT_SRC[@]}" | wc -l)"
  n_page="$(scan_kt '^fun [A-Z][A-Za-z0-9_]*(Page|Screen)[[:space:]]*\(' "${KT_SRC[@]}" | wc -l)"
  if [ "$n_entry" -eq 0 ]; then
    bad "没有任何 entry<Route.Xxx> 分支" "NavDisplay 的 entryProvider 为空，运行时切任何路由都拿不到 composable"
  else
    ok "有 $n_entry 个 entry<> 分支"
  fi
  if [ "$n_page" -eq 0 ]; then
    bad "没有任何页面级 composable（fun XxxPage/XxxScreen）" "导航接了但没页面可接"
  else
    ok "有 $n_page 个页面级 composable"
  fi
  if [ "$n_entry" -gt "$n_ser" ]; then
    bad "entry<> 有 $n_entry 个，但 @Serializable 只有 $n_ser 处" \
        "每个路由对象都要 @Serializable，缺的那个在编译期报 Serializer for class ... is not found"
  fi
  if [ "$n_entry" -ne "$n_page" ]; then
    warn "entry<>（$n_entry）与页面 composable（$n_page）数量不等" \
        "不一定是错（同一页面可多路由、也可有非 Page 命名的 composable），但请核对每个路由都有落点"
  fi
else
  bad "无 .kt 源码，导航接线无法校验" "见「工程结构」节的缺源码条目"
fi

# ---- 11. 主题与持久化 ----
start_section "主题与持久化"
if [ "${#KT_SRC[@]}" -gt 0 ]; then
  tc_lines="$(scan_kt 'ThemeController[[:space:]]*\(' "${KT_SRC[@]}")"
  if [ -z "$tc_lines" ]; then
    bad "代码里没有 ThemeController" \
        "自定义主题色/色板模式只能通过 ThemeController 传给 MiuixTheme，缺则主题设置无处生效"
  else
    ok "有 ThemeController（$(printf '%s\n' "$tc_lines" | wc -l) 处）"
    # ThemeController 是 data class 且属性全 val，切换主题只能整体重建 -> 必须包在 remember 里，
    # 否则每次重组都新建 controller，MiuixTheme 下游全量失效（表现为动画乱跳/输入框掉焦点）。
    tc_bad=0
    while IFS=: read -r f ln _rest; do
      [ -n "$f" ] && [ -n "$ln" ] || continue
      prev="$(strip_code "$f" | head -n "$ln" | tail -n 11)"
      if ! grep -Eq 'remember[[:space:]]*\(' <<<"$prev"; then
        tc_bad=$((tc_bad+1))
        [ "$tc_bad" -le 3 ] && bad "$f:$ln ThemeController 不在 remember 里" \
          "controller 属性全 val，只能重建；不 remember 的话每次重组都新建，主题状态被反复重置"
      fi
    done <<<"$tc_lines"
    [ "$tc_bad" -eq 0 ] && ok "每处 ThemeController 都在 remember(...) 内构造"
  fi
  if any_kt 'interface[[:space:]]+AppPrefs' "${KT_SRC[@]}"; then
    ok "有 interface AppPrefs（commonMain 抽象）"
  else
    bad "没有 interface AppPrefs" \
        "commonMain 拿不到 SharedPreferences；持久化必须先抽接口，由 androidMain/iosMain 各给实现"
  fi
  # 写回判定：`=` 后面必须不是 `=`，否则 `prefs.themeMode == m` 这种比较表达式
  # 会被当成「有写回」——变异测试 B04 就是把三处写回全改成 == 之后仍然 PASS。
  if any_kt 'prefs\.[a-zA-Z_]+[[:space:]]*=[^=]' "${KT_SRC[@]}"; then
    ok "有 prefs.xxx = ... 写回（设置能落盘）"
  else
    bad "没有任何 prefs.xxx = ... 写回" \
        "只有 mutableStateOf(prefs.x) 读取、没有写回的话，改完主题杀掉 App 就回到默认值"
  fi
  if any_kt 'getSharedPreferences|SharedPreferencesAppPrefs' "${KT_SRC[@]}"; then
    ok "Android 侧有 SharedPreferences 实现"
  else
    bad "没有基于 SharedPreferences 的持久化实现" "接口有了但没人实现，App 启动时构造 prefs 就会失败"
  fi
  if any_kt 'MiuixTheme[[:space:]]*\(' "${KT_SRC[@]}"; then
    ok "有 MiuixTheme 包裹"
  else
    bad "没有 MiuixTheme" "miuix 组件依赖它提供的 LocalTheme 等 CompositionLocal"
  fi
else
  bad "无 .kt 源码，主题与持久化无法校验"
fi

# ---- 12. 液态玻璃与降级分支 ----
start_section "液态玻璃"
if [ "${#KT_SRC[@]}" -gt 0 ]; then
  # 本节一律只看 KT_SRC（仓库真正会构建的源码），不看 KT_ALL。
  # 之前 has_blur/has_gate 用 KT_ALL，把 skills/…/assets/liquid/ 下那份「抄进新项目」的
  # 镜像也算进作用域：把仓库源码里的 isRuntimeShaderSupported() 全删掉，镜像里那份
  # 还在，检查照样 PASS——同一节里 lb_files 又用的是 KT_SRC，两种作用域混用。
  # 镜像本身对不对由「模板镜像」节用 diff 单独管。
  has_blur="$(scan_kt 'textureBlur' "${KT_SRC[@]}")"
  has_gate="$(scan_kt 'isRuntimeShaderSupported[[:space:]]*\([[:space:]]*\)' "${KT_SRC[@]}")"
  if [ -n "$has_blur" ]; then
    ok "有 textureBlur（$(printf '%s\n' "$has_blur" | wc -l) 处）"
    if [ -z "$has_gate" ]; then
      bad "用了 textureBlur 但仓库源码里没有 isRuntimeShaderSupported()" \
          "blur 需 RuntimeShader（Android 12+）；工程 minSdk 24 能装到低版本机器上，缺降级分支就是运行期崩溃"
    else
      ok "有 isRuntimeShaderSupported() 判定"
    fi
  else
    info "没有 textureBlur" "未使用液态玻璃，跳过 RuntimeShader 门控检查"
  fi
  if [ -n "$has_gate" ] && [ -z "$has_blur" ]; then
    warn "有 isRuntimeShaderSupported() 但没有 textureBlur" "门控写了却没实际用到 blur，检查降级分支是否接错"
  fi
  if [ -n "$(scan_kt 'rememberLayerBackdrop' "${KT_SRC[@]}")" ]; then
    ok "有 rememberLayerBackdrop（layer 注册侧）"
  else
    if [ -n "$has_blur" ]; then
      bad "用了 textureBlur 但没有 rememberLayerBackdrop" \
          "textureBlur 的 backdrop 参数需要一个 LayerBackdrop；没有注册层就没有可采样的内容"
    else
      info "没有 rememberLayerBackdrop"
    fi
  fi
  # 同一个 LayerBackdrop 实例既被祖先 layerBackdrop 注册、又被其后代 textureBlur 采样，
  # 会在 Android 上形成 RenderNode 父子环，prepareTree 无限递归直接 native 崩溃。
  lb_files="$(scan_kt 'layerBackdrop[[:space:]]*\(' "${KT_SRC[@]}" | sed -E 's/:[0-9]+:.*$//' | sort -u)"
  if [ -n "$lb_files" ]; then
    ok "有 layerBackdrop 注册点（$(printf '%s\n' "$lb_files" | wc -l) 个文件）"
  else
    if [ -n "$has_blur" ]; then
      warn "用了 textureBlur 但没找到 layerBackdrop(...)" "backdrop 层需要在祖先节点上注册，否则采样到空内容"
    fi
  fi
else
  bad "无 .kt 源码，液态玻璃降级分支无法校验"
fi

# ---- 13. API 误用（源码实证）----
# 下面每一条都是把 miuix 的 klib 解包、对着声明核对过的「写了就编不过/运行不对」的形态。
# 一律先剥注释再匹配：pitfalls.md 与模板注释里大量出现这些名字的反例写法。
start_section "API 误用（源码实证）"
if [ "${#KT_ALL[@]}" -eq 0 ]; then
  bad "无 .kt 源码，API 误用检查无法执行"
else
  report_hits() {  # $1=结论 $2=说明 $3=命中列表
    local n
    n="$(printf '%s\n' "$3" | grep -c .)"
    bad "$1（$n 处）" "$(printf '%s\n' "$3" | head -3)
$2"
  }
  # ScrollBehavior 只有 overScroll / collapsedFraction / canScroll 三个可取值，
  # 连接对象叫 nestedScrollConnection（在 Modifier 上，不在 behavior 上）。
  # 接收者名不能写死成 scrollBehavior：变量叫 bar/behavior/sb 一样编不过
  # （变异测试 B08 证明旧写法对 `bar.nestedScroll` 完全放行）。
  # 排除 import 行：App.kt 里 `import ...nestedscroll.nestedScroll` 的行尾正好落在 $ 上。
  hits="$(scan_kt '\b[A-Za-z0-9_]+\.nestedScroll([^C(]|$)' "${KT_ALL[@]}" \
            | grep -vE ':[0-9]+:[[:space:]]*import[[:space:]]' || true)"
  if [ -n "$hits" ]; then
    report_hits "把 .nestedScroll 当属性读（正确成员是 .nestedScrollConnection）" \
      "ScrollBehavior 上没有 nestedScroll 成员；正确写法是 Modifier.nestedScroll(scrollBehavior.nestedScrollConnection)" \
      "$hits"
  else
    ok "无 scrollBehavior.nestedScroll 误用"
  fi
  hits="$(scan_kt 'nestedScroll\.connection' "${KT_ALL[@]}")"
  if [ -n "$hits" ]; then
    report_hits "写了 nestedScroll.connection" "没有这个成员；同上，应为 scrollBehavior.nestedScrollConnection" "$hits"
  else
    ok "无 nestedScroll.connection 误用"
  fi
  # Scaffold 的签名里没有 scrollBehavior（那是 material3 的参数），写了编不过。
  # 用 scan_direct_arg 而不是行内正则：多行写法也要抓到，且不能把嵌在 topBar lambda 里
  # 的合法 TopAppBar(scrollBehavior = ...) 误报（变异测试 A01 证明旧写法只抓得到单行）。
  hits="$(scan_direct_arg Scaffold scrollBehavior "${KT_ALL[@]}")"
  if [ -n "$hits" ]; then
    report_hits "Scaffold(...) 里传了 scrollBehavior" \
      "miuix 的 Scaffold 没有 scrollBehavior 参数（material3 才有）；折叠顶栏请直接用 TopAppBar 的 scrollBehavior，并把 Modifier.nestedScroll(...) 加在滚动容器上" \
      "$hits"
  else
    ok "Scaffold 未被塞进 scrollBehavior"
  fi
  # 全库没有 PreferenceCategory / PreferenceGroup / PreferenceScreen，分组标题只有 SmallTitle。
  hits="$(scan_kt '\b(PreferenceCategory|PreferenceGroup|PreferenceScreen)[[:space:]]*\(' "${KT_ALL[@]}")"
  if [ -n "$hits" ]; then
    report_hits "用了 PreferenceCategory/PreferenceGroup/PreferenceScreen" \
      "miuix-preference 里这三个都不存在（那是 androidx.preference 的类名）；分组标题用 SmallTitle，条目用 PreferenceGroup 里的等价组件" \
      "$hits"
  else
    ok "无 PreferenceCategory/PreferenceGroup/PreferenceScreen 误用"
  fi
  # NavigationItem 只有 label / icon 两个字段，没有 selectedIcon / badge（material3 BottomAppBar 的参数名）。
  hits="$(scan_kt 'NavigationItem[[:space:]]*\(' "${KT_ALL[@]}" | sed -E 's/:[0-9]+:.*$//' | sort -u)"
  nav_bad=""
  if [ -n "$hits" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      h="$(strip_code "$f" | grep -nE -A4 'NavigationItem[[:space:]]*\(' | grep -E 'selectedIcon|badge[[:space:]]*=' | sed "s|^|$f:|" || true)"
      [ -n "$h" ] && nav_bad="$nav_bad$h
"
    done <<<"$hits"
  fi
  if [ -n "$nav_bad" ]; then
    report_hits "NavigationItem 传了 selectedIcon/badge" \
      "miuix 的 NavigationItem 只有 label 与 icon；选中态由 BottomBar 的 selectedIndex 驱动，不要按 material3 的参数名写" \
      "$(printf '%s' "$nav_bad")"
  else
    ok "NavigationItem 参数用法正确（无 selectedIcon/badge）"
  fi
  # ThemeController 属性全 val，只能重建，不能赋值。变量名不固定（controller /
  # ctrl / themeCtrl / sbController 都会出现），写死 `controller\.` 等于只防一种手滑
  # （变异测试 B07：注入 `themeCtrl.colorMode = 1` 旧写法完全放行）。
  hits="$(scan_kt '\b[A-Za-z0-9_]*([Cc]ontroller|[Cc]trl)[A-Za-z0-9_]*\.[a-zA-Z_]+[[:space:]]*=[^=]' "${KT_ALL[@]}")"
  if [ -n "$hits" ]; then
    report_hits "对 *Controller/*Ctrl 属性赋值" \
      "ThemeController 的属性全是 val（只读），切换主题只能 remember 重建一个新 controller" "$hits"
  else
    ok "无 controller.xxx = 赋值"
  fi
  # commonMain 里不能出现 JVM-only API。
  cm_files=()
  for f in ${KT_ALL[@]+"${KT_ALL[@]}"}; do case "$f" in */src/commonMain/*) cm_files+=("$f") ;; esac; done
  if [ "${#cm_files[@]}" -gt 0 ]; then
    hits="$(scan_kt 'System\.currentTimeMillis|java\.util\.(Date|LocalDate)|Thread\.sleep|java\.time\.' "${cm_files[@]}")"
    if [ -n "$hits" ]; then
      report_hits "commonMain 里用了 JVM-only API" \
        "commonMain 编译到所有目标（含 iOS/JS），java.* 与 System.* 都不存在；请改成 expect fun ... 并在 androidMain 给 actual" \
        "$hits"
    else
      ok "commonMain 无 JVM-only API（${#cm_files[@]} 个文件）"
    fi
  else
    info "没有 commonMain 源文件"
  fi
  # Modifier.blur 是 compose foundation 的高斯模糊，与 miuix-blur 的液态玻璃不是一回事
  hits="$(scan_kt 'Modifier\.blur[[:space:]]*\(' "${KT_ALL[@]}")"
  if [ -n "$hits" ]; then
    n="$(printf '%s\n' "$hits" | grep -c .)"
    warn "用了 Modifier.blur（$n 处）" "foundation 的高斯模糊不是 miuix 的液态玻璃；液态玻璃请用 textureBlur + LayerBackdrop"
  fi
fi

# ---- 14. 签名配置 ----
start_section "签名"
if need_file "$APP_BG" "app/build.gradle.kts"; then
  if cgrep "$APP_BG" 'signingConfig'; then
    if cgrep "$APP_BG" 'storeType[[:space:]]*=[[:space:]]*"PKCS12"'; then
      ok "signingConfig 显式 storeType = \"PKCS12\""
    else
      bad "signingConfig 缺 storeType = \"PKCS12\"" \
          "openssl 产的是 PKCS12，AGP 按默认 JKS 读会失败"
    fi
  else
    warn "app 里没有 signingConfig" "没有它 CI 只会产出 app-release-unsigned.apk（装不上）"
  fi
fi
if [ -f "$ROOT/.gitignore" ]; then
  # 必须剥掉注释行再判定：`# *.p12` 是「这条规则被关掉了」，不是「已覆盖」。
  # 变异测试 B09 证明不剥注释时，把四行全注释掉仍然 PASS。
  # 同时剥掉 `!` 取反行——`!**/*.p12` 是放行而不是忽略，不能算覆盖。
  gi_body="$(grep -vE '^[[:space:]]*[#!]' "$ROOT/.gitignore" || true)"
  miss=""
  for pat in '*.p12' '*.jks' '*.keystore' 'local.properties'; do
    grep -qF -- "$pat" <<<"$gi_body" || miss="$miss $pat"
  done
  if [ -z "$miss" ]; then
    ok ".gitignore 覆盖 keystore 与 local.properties"
  else
    bad ".gitignore 缺:$miss" "私钥/口令一旦提交，public 仓库等于公开"
  fi
else
  bad "缺 .gitignore"
fi
leaked="$(find "$ROOT" \( -name build -o -name .git \) -prune -o \
             \( -name '*.p12' -o -name '*.jks' -o -name '*.keystore' \) -print 2>/dev/null)"
if [ -z "$leaked" ]; then
  ok "仓库里没有已提交的 keystore 二进制"
else
  bad "仓库里有 keystore 二进制：$(printf '%s\n' "$leaked" | head -3 | tr '\n' ' ')" \
      "即便 .gitignore 写了，已提交的历史仍在；请轮换并清历史"
fi

# ---- 15. workflow ----
# 检查按用途门控：不是每个 workflow 都构建 APK，对 dependency-review 这类
# 只读 workflow 要求「签名校验步骤」只会制造噪音。
start_section "GitHub Actions"
if [ -d "$WORKFLOW_DIR" ]; then
  ymls="$(find "$WORKFLOW_DIR" \( -name '*.yml' -o -name '*.yaml' \) -print 2>/dev/null)"
  if [ -n "$ymls" ]; then
    ok "workflows 目录有 yml"
  else
    bad "workflows 目录为空"
  fi
  build_yml=""
  for y in $ymls; do
    n="$(basename "$y")"
    body="$(strip_code "$y")"
    # 全通用：secrets 出现在 if: 里对任何 workflow 都是致命的
    if grep -qE '^[[:space:]]*if:.*secrets\.' <<<"$body"; then
      bad "$n: step 级 if: 里引用了 secrets.*" \
          "secrets 不在 if 上下文里，会导致 workflow 解析成 0 个 job；判断请写进 shell step 内部"
    else
      ok "$n: if: 里没有 secrets.*"
    fi

    if grep -qE 'action-gh-release|softprops' <<<"$body"; then
      if grep -qE 'contents:[[:space:]]*write' <<<"$body"; then
        ok "$n: 创建 Release，且已授予 contents: write"
      else
        bad "$n: 创建 Release 但缺 permissions contents: write" \
            "缺省 GITHUB_TOKEN 只有 read，会 403 Resource not accessible by integration"
      fi
    fi

    if grep -qE 'assembleRelease|assemble-release' <<<"$body"; then
      build_yml="$y"
      if grep -qF './gradlew' <<<"$body"; then
        warn "$n: 用了 ./gradlew" "仓库未提交 wrapper jar，CI 应直接用 gradle（由 setup-gradle 提供）"
      else
        ok "$n: 构建 APK，且不依赖未提交的 wrapper"
      fi
      if grep -qE 'apksigner|unsigned' <<<"$body"; then
        ok "$n: 有签名校验兜底步骤"
      else
        warn "$n: 构建 release 但没有签名校验步骤" \
            "建议：产物名含 unsigned 就 exit 1，再 apksigner verify --print-certs"
      fi
      if grep -qE 'setup-java' <<<"$body"; then
        ok "$n: 有 setup-java"
      else
        bad "$n: 构建 APK 却没有 actions/setup-java" "runner 上的默认 JDK 版本不受控，AGP 会报 JDK 版本不足"
      fi
      if grep -qE 'java-version:[[:space:]]*"?21' <<<"$body"; then
        ok "$n: java-version 21"
      else
        warn "$n: java-version 不是 21" "AGP 9 的最低 JDK 更高，模板实测用 21"
      fi
      if grep -qE 'MIUIX_KEYSTORE_B64|KEYSTORE' <<<"$body"; then
        ok "$n: 从 secrets 还原 keystore"
      else
        warn "$n: 没有从 secrets 还原 keystore 的步骤" "没有它 CI 只能出 unsigned 包"
      fi
    fi
  done
  if [ -z "$build_yml" ]; then
    bad "没有任何 workflow 执行 assembleRelease" \
        "无 JDK 环境下 CI 是唯一能真正构建/签名的地方；缺这条等于这个仓库永远不会产出 APK"
  fi
else
  bad "缺 .github/workflows 目录" "无 JDK 环境下 CI 是唯一能真正构建/签名的地方"
fi

# ---- 16. assets 镜像漂移 ----
# assets/workflow-build-apk.yml 是仓库那份 workflow 的镜像，只用于新项目起点。
# 仓库里的 .github/workflows/build-apk.yml 才是权威；镜像一旦落后，就会教人把
# 旧版本抄回去——漂移的模板比没有模板更糟。本次重构中它就真的落后过一次
# （仓库把 actions/download-artifact 从 v7 升到 v8，镜像没跟上）。
start_section "模板镜像"
MIRROR="$(find_one 'workflow-build-apk.yml')"
# 权威版不能写死成 build-apk.yml：第 15 节已经按「哪个 workflow 真的执行
# assembleRelease」算出 build_yml，改名（release.yml / publish.yml）之后写死的
# 路径就不存在了，旧代码于是静默走 else 打一条 info——整节检查凭空消失
# （变异测试 B13：把 build-apk.yml 改名 release.yml，rc 仍为 0）。
LIVE="${build_yml:-}"
if [ -z "$MIRROR" ] && [ -z "$LIVE" ]; then
  info "既无 workflow 镜像也无构建 workflow（派生仓库一般不带 skills/…/assets/），跳过"
elif [ -z "$MIRROR" ]; then
  info "仓库有构建 workflow 但没有 assets 镜像（派生仓库不带 skills/…/assets/ 时正常），跳过"
elif [ -z "$LIVE" ]; then
  warn "assets 里有 workflow 镜像，但仓库没有任何执行 assembleRelease 的 workflow" \
       "镜像无从比对，等于一份没人校验的副本；要么补回构建 workflow，要么删掉镜像"
else
  drift="$(diff <(strip_code "$MIRROR" | grep -vE '^[[:space:]]*$') \
               <(strip_code "$LIVE" | grep -vE '^[[:space:]]*$') | head -8)"
  if [ -z "$drift" ]; then
    ok "assets 的 workflow 镜像与 $(basename "$LIVE") 一致（忽略注释与空行）"
  else
    warn "assets 的 workflow 镜像与 $LIVE 漂移" \
         "以仓库那份为准并同步镜像。前几处差异: $(echo "$drift" | tr '\n' ' | ')"
  fi
fi

close_section

echo
echo "== 结果：PASS=$PASS FAIL=$FAIL WARN=$WARN =="
if [ "$FAIL" -gt 0 ]; then
  echo "存在 $FAIL 项硬失败，先修掉再交付（对应说明见 references/pitfalls.md）。"
  exit 1
fi
echo "静态检查通过。注意：grep 级检查不能证明能编译——"
echo "构建、二进制、运行时三类检测仍需 gradle/SDK 或 GitHub Actions 实跑。"
