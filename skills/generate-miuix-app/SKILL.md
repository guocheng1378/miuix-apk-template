---
name: generate-miuix-app
description: 从零生成或改造一个 MIUIX 风格的 Android APK 工程——Compose Multiplatform(KMP) + miuix 组件库，带悬浮液态玻璃底栏、miuix-nav 页面栈导航、大标题折叠 TopAppBar、下拉刷新、Coil3 图集、miuix-preference 设置页、主题跨重启持久化与 edge-to-edge，并配好 GitHub Actions 的 Release 构建、PKCS12 正式签名与签名校验兜底。当用户要求「生成 MIUIX 风格 app」「套壳 MIUIX」「用 miuix 搭 Android 界面」「液态玻璃/悬浮玻璃底栏」「miuix-nav 导航应用」「miuix 签名 APK 构建」，或要在已有 miuix-apk-template 仓库上派生新应用时使用。本 skill 只负责静态生成与自检，实际编译与签名在 GitHub Actions 完成。
metadata:
  version: "1.0.0"
  upstream-miuix: "top.yukonga.miuix.kmp 0.9.4-rc01 (github.com/compose-miuix-ui/miuix)"
  template-repo: "https://github.com/guocheng1378/miuix-apk-template"
  compatibility: 本机不需要 JDK / Android SDK / adb——编译、签名、产物校验全部在 GitHub Actions runner 上完成，本 skill 只做静态生成与 grep 级自检。scripts/gen-keystore.sh 与 scripts/preflight.sh 需要 bash + openssl；scripts/set-gh-secrets.py 需要 python3 + pynacl（建议装进 venv）；scripts/lint-skill.py 只需要 python3 标准库。网络需可达 repo1.maven.org、dl.google.com、api.github.com、raw.githubusercontent.com。写 Secrets 或推 tag 触发 CI 需要 GitHub token。
---

# 生成 MIUIX 风格 APK 应用

本文件只做**路由与硬约束**。细节按下面的表按需加载到 `references/`，不要一次全读——
大部分任务只需要其中一到两个文件。

## 何时使用

- 「生成一个 MIUIX 风格的 app」/「用 miuix 搭建 Android 界面」/「套壳 MIUIX」
- 「液态玻璃底栏」/「悬浮玻璃导航栏」/「iOS 风液态玻璃」
- 「miuix-nav 页面栈导航」/「大标题折叠 TopAppBar」
- 点名 MIUIX 组件库、要原生 Android 界面 + Release APK 产出的请求
- 在已有 `miuix-apk-template` 仓库上派生新应用（改包名/应用名/主题色/页面）

配好签名 Secrets 才产出**已签名** APK；否则只能产出 unsigned release。

## 按需加载（Load Order）

先判断任务落在哪一类，只读对应的 `references/` 文件：

| 你的意图 | 读这个 |
|---|---|
| 写/改 `build.gradle.kts`、`settings.gradle.kts`、`gradle.properties`、wrapper；版本选型 | `references/stack-and-build.md` |
| 写 Compose 代码：miuix import 路径、真实签名、导航/blur/preference/theme 接线、液态玻璃组件 | `references/miuix-api.md` |
| 大标题折叠不生效、`TopAppBar` 与 `PullToRefresh` 怎么联动 `ScrollBehavior`、`textureBlur` 传参类型不匹配 | `references/pitfalls.md` I 节（滚动接线）＋ A 节（编译期签名） |
| 产出 keystore、配 Signing Secrets、无 JDK 环境补签名 | `references/signing-and-secrets.md` |
| 写/修 `.github/workflows/build-apk.yml`，CI 报 403 / 0 jobs / 装不上的包 | `references/ci-workflow.md` |
| 核验某个 API 或版本是否属实（**流程见上面「API 核对标准流程」**）；交付前检测清单；本机没 JDK 时能做到哪一步 | `references/verification.md` |
| 撞上编译错误 / 依赖解析失败 / 文档与实际不符——**先查这里再动手** | `references/pitfalls.md` |
| **做液态玻璃底栏**：不要照签名自己重写这 7 个组件，直接拷成品源码 | `assets/liquid/`（先读 `assets/liquid/README.md`） |

**液态玻璃组件是资产、不是文档。** `assets/liquid/component/` 下 7 个 `.kt`
（`liquid/` 5 个 + `animation/` 2 个）是可直接编译的成品源码，与模板仓库
`shared/src/commonMain/kotlin/component/` 逐字节一致；`assets/liquid/snippets/` 两个
`.kt.snippet` 是接线写法。**生成新工程时整目录原样拷过去**，只按 README 改包名，
不要重新实现——`textureBlur`/`layerBackdrop`/`Highlight` 的真实参数组合和「一个 backdrop
实例一个注册点」那条（不可协商项 12）都固化在这批源码里，手写极易踩 G1 那个首帧 SIGSEGV。

已有参考实现（如本仓库）时**优先派生**：以它为基线改包名/应用名/主题色/页面，
而不是从空白重写。从零生成时按 `stack-and-build.md` 的目录结构建。

## 不可协商项（Non-Negotiables）

这些是踩过坑或实测出来的硬前提，违反任一条就直接失败：

1. **`compileSdk = 37`**。miuix `0.9.4-rc01` 的 AAR 声明 `minCompileSdk=37`（解包 `aar-metadata.properties` 实测），低于 37 构建直接失败。
2. **`miuix-blur` 在 Android 侧要求 `minSdk 33`**（解包其 AAR 的 `AndroidManifest.xml` 实测）。模板整体 `minSdk = 24`，靠 Manifest 里 `<uses-sdk tools:overrideLibrary="top.yukonga.miuix.kmp.blur" />` 放行，因此**必须**保留运行时的 `isRuntimeShaderSupported()` 降级分支。
3. **`app` 模块不得应用 `org.jetbrains.kotlin.android`**。AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报 `Remove the 'org.jetbrains.kotlin.android' plugin`。
4. **`shared` 模块用 `com.android.kotlin.multiplatform.library`**，不能用 `com.android.library`（与 KMP 扩展名冲突）；Android 目标内联在 `kotlin { android { ... } }`，没有顶层 `android {}` 块、不调用 `androidTarget()`。
5. **`coil-network-okhttp` 只能放 `androidMain`**（commonMain 无该变体），否则依赖解析失败。
6. **`secrets.*` 不得出现在 step 级 `if:`**，否则整个 workflow 被解析成 0 个 job；判断要写进 shell step 内部。
7. **workflow 顶层必须 `permissions: contents: write`**，否则创建 Release 步骤 403 `Resource not accessible by integration`。
8. **走 PKCS12 必须显式 `storeType = "PKCS12"`**，否则 AGP 按默认 JKS 读取失败。
9. **仓库是 public 时绝不把 keystore 当 workflow artifact 上传**——artifact 可被任何持 token 者下载，等于泄露私钥。只走 Secrets。
10. **PyNaCl 用 `public.SealedBox`，不是 `Box`**。GitHub Secrets 加密方案是 sealed box。
11. **绝不回显用户提供的 token**；PAT 明文出现在对话里就建议其立即撤销。
12. **一个 `LayerBackdrop` 实例只能有一个注册点，且采样者不得是注册点的后代**。
    `Modifier.layerBackdrop(b)` 把当前节点整棵子树录进 `b.graphicsLayer`（Android 上就是
    一个 `RenderNode`），`textureBlur`/`drawBackdrop` 用 `drawRenderNode` 重放它、建立真实
    父子边。若采样者 `N` 落在注册者 `M` 的子树内且用同一个 `b`，RenderNode 图成环 →
    **首帧 SIGSEGV，backtrace 是 512 层 `RenderNode::prepareTreeImpl` 且一帧 Kotlin 都没有**。
    安全接法：content 槽注册、`bottomBar` 槽采样（两者是 Scaffold 的兄弟槽位）；页面内的
    玻璃元素另起独立 `rememberLayerBackdrop()` 实例并注册在纯装饰背景兄弟层上。
    这条**静态检查抓不到**（祖先/后代是布局树属性），只能靠 emulator 冒烟 job 兜。
    详见 `references/pitfalls.md` G1。

## 版本矩阵（CI 端到端编译验证过的组合，非推测）

| 项 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`miuix-ui` + `miuix-icons` + `miuix-blur` + `miuix-nav` + `miuix-preference` + `miuix-squircle`；另有 `miuix-core` 由 `miuix-ui` 的 POM 以 `runtime` 传递带入，**不必显式声明**，但 `MiuixIcons` 壳对象在它里面，下 sources jar 核对时别漏——共 7 个模块） |
| Coil | `3.6.1`（`coil-compose` 在 commonMain，`coil-network-okhttp` 在 androidMain） |
| kotlinx-serialization | `1.11.0` |
| androidx.activity-compose | `1.13.0` |
| compileSdk / targetSdk | `37` |
| minSdk | `24`（blur 需 33，见不可协商项 2） |
| JDK（CI） | `21`（Zulu） |
| Gradle | `9.7.1`（`gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`） |

MIUIX 的版本以 **Maven Central** 为准。miuix **有** GitHub Releases
（`github.com/compose-miuix-ui/miuix/releases`），但 rc 版标了 `prerelease`，而
`/releases/latest` 端点按定义排除 prerelease（实测只回 `v0.9.3`，不是 `v0.9.4-rc01`）——
查版本用 `/releases` 或 `/tags`，别用 `/latest`。Release 页只当变更日志读，
jar/aar 只在 Central。核实方法见下面「API 核对标准流程」。

## API 核对标准流程（下 sources jar）

**规则：任何 miuix 的函数签名、参数名、可空性、默认值、SDK 门槛，在写进代码或本 skill 的
文档之前，都要用下面的流程实测一遍。不要凭记忆写，也不要照抄上一版文档——本 skill 就曾经
把 `Scaffold` 的滚动接管写反过（见 `references/pitfalls.md` I 节）。**

网络需可达 `repo1.maven.org`。`$V` 用版本矩阵里的 MIUIX 版本。

```bash
V=0.9.4-rc01
BASE=https://repo1.maven.org/maven2/top/yukonga/miuix/kmp
M=miuix-ui          # ui / icons / blur / nav / preference / squircle / core 都有 sources jar（实测 200）
mkdir -p /tmp/mx && cd /tmp/mx
curl -sSL -o $M.jar "$BASE/$M/$V/$M-$V-sources.jar" && unzip -qo $M.jar -d $M
```

**关键差异：`<module>-android-<ver>-sources.jar` 是超集。** 实测普通
`$M-$V-sources.jar` 只含 `commonMain/` 与 `skikoMain/`；而 `$M-android-$V-sources.jar`
**同时**含 `androidMain/`（如 `blur/internal/RenderEffectCompat.android.kt`）和
`commonMain/`。所以**核对 Android 行为时直接下 `-android` 那个 jar 就够了**，不用下两个。
AAR 坐标同理是 `$M-android-$V.aar`。

核对签名（示例即 `pitfalls.md` I 节与 A 节的实证来源）。注意 sources jar 解出来的路径
**没有** `kotlin/` 这一层，是 `commonMain/top/yukonga/miuix/kmp/basic/…`，所以用 `find` 定位
比手写相对路径稳：

```bash
f=$(find . -name Scaffold.kt -path '*/basic/*'); grep -n "fun Scaffold" -A 14 "$f"
t=$(find . -name TopAppBar.kt -path '*/basic/*'); sed -n '422,455p' "$t"   # interface ScrollBehavior 的成员
grep -rn "ScrollBehavior" --include=*.kt .                                 # 全库只有 TopAppBar.kt / PullToRefresh.kt
```

核对 SDK 门槛（**不要**猜，AAR 里写着）：

```bash
M=miuix-blur        # 换模块再跑一遍：门槛是逐模块声明的
curl -sSL -o $M.aar "$BASE/$M-android/$V/$M-android-$V.aar"
unzip -p $M.aar META-INF/com/android/build/gradle/aar-metadata.properties   # → minCompileSdk=37
unzip -p $M.aar AndroidManifest.xml | tr -c '[:print:]' '\n' | grep -o 'minSdkVersion="[0-9]*"'  # → 33（blur）
```

（`AndroidManifest.xml` 在 AAR 里是**二进制 XML**，直接 `grep` 读不出来，所以先
`tr -c '[:print:]' '\n'` 把不可见字节换成换行。）

`aar-metadata.properties` 的 `minCompileSdk` 是**硬失败**（AGP 直接拒绝构建），
`AndroidManifest.xml` 的 `minSdkVersion` 靠 `tools:overrideLibrary` 可放行但运行期要降级分支——
两者性质不同，别混为一谈。不可协商项 1、2 就是这么测出来的。
实测 0.9.4-rc01 各模块：`minCompileSdk` **全部 37**；`minSdkVersion` 除 `miuix-blur` 是
**33** 外，`ui`/`nav`/`preference` 均为 **24**（rc01 把下限从 23 抬到了 24，写在它的 release
body 里）。所以「blur 需 33、其余需 24」——模板整体 `minSdk = 24` 只对非 blur 模块成立，
blur 那条是靠 `overrideLibrary` 强过的。

查版本/变更日志：`GET api.github.com/repos/compose-miuix-ui/miuix/releases`（**不是**
`/releases/latest`，它排除 prerelease）。rc 版的 release body 里写了破坏性变更（如
`minSdk 23→24`、`miuix-navigation3-ui` 移除换成 `miuix-nav`），升级前必读。
写文档时只引「grep 得到的那一行」，行号连同文件名一起写，方便下一个人复核。

## 脚本

| 脚本 | 用途 | 依赖 |
|---|---|---|
| `scripts/preflight.sh` | 对目标仓库跑 grep 级静态自检，逐项 PASS/FAIL，任一 FAIL 退出码 1 | bash |
| `scripts/gen-keystore.sh` | 无 JDK/keytool 时用 openssl 产 PKCS12 + base64 | bash + openssl |
| `scripts/set-gh-secrets.py` | 用 GitHub API 加密写入 Signing Secrets | python3 + pynacl |

交付前**必须**跑一次 `bash scripts/preflight.sh`。

## 安全与凭证

生成仓库、打 tag、触发 CI 需要 GitHub 凭证。只在用户明确提供时用于一次性
`git remote add` + `push`，push 后立即 `git remote set-url origin <不含 token 的 URL>`
清理 `.git/config`。keystore 与口令要异地备份——丢了它，同一 `applicationId`
再也无法覆盖升级到已装用户机上。
