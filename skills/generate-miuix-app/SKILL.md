---
name: generate-miuix-app
description: 从零生成或改造一个 MIUIX 风格的 Android APK 工程——Compose Multiplatform(KMP) + miuix 组件库，带悬浮液态玻璃底栏、miuix-nav 页面栈导航、大标题折叠 TopAppBar、下拉刷新、Coil3 图集、miuix-preference 设置页、主题跨重启持久化与 edge-to-edge，并配好 GitHub Actions 的 Release 构建、PKCS12 正式签名与签名校验兜底。当用户要求「生成 MIUIX 风格 app」「套壳 MIUIX」「用 miuix 搭 Android 界面」「液态玻璃/悬浮玻璃底栏」「miuix-nav 导航应用」「miuix 签名 APK 构建」，或要在已有 miuix-apk-template 仓库上派生新应用时使用。本 skill 只负责静态生成与自检，实际编译与签名在 GitHub Actions 完成。
compatibility: 本机不需要 JDK / Android SDK / adb——编译、签名、产物校验全部在 GitHub Actions runner 上完成，本 skill 只做静态生成与 grep 级自检。scripts/gen-keystore.sh 与 scripts/preflight.sh 需要 bash + openssl；scripts/set-gh-secrets.py 需要 python3 + pynacl（建议装进 venv）。网络需可达 repo1.maven.org、dl.google.com、api.github.com、raw.githubusercontent.com。写 Secrets 或推 tag 触发 CI 需要 GitHub token。
metadata:
  version: "1.0.0"
  upstream-miuix: "top.yukonga.miuix.kmp 0.9.4-rc01 (github.com/compose-miuix-ui/miuix)"
  template-repo: "https://github.com/guocheng1378/miuix-apk-template"
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
| 产出 keystore、配 Signing Secrets、无 JDK 环境补签名 | `references/signing-and-secrets.md` |
| 写/修 `.github/workflows/build-apk.yml`，CI 报 403 / 0 jobs / 装不上的包 | `references/ci-workflow.md` |
| 核验某个 API 或版本是否属实；交付前检测清单；本机没 JDK 时能做到哪一步 | `references/verification.md` |
| 撞上编译错误 / 依赖解析失败 / 文档与实际不符——**先查这里再动手** | `references/pitfalls.md` |

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

## 版本矩阵（CI 端到端编译验证过的组合，非推测）

| 项 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`miuix-ui` + `miuix-icons` + `miuix-blur` + `miuix-nav` + `miuix-preference` + `miuix-squircle`） |
| Coil | `3.6.1`（`coil-compose` 在 commonMain，`coil-network-okhttp` 在 androidMain） |
| kotlinx-serialization | `1.11.0` |
| androidx.activity-compose | `1.13.0` |
| compileSdk / targetSdk | `37` |
| minSdk | `24`（blur 需 33，见不可协商项 2） |
| JDK（CI） | `21`（Zulu） |
| Gradle | `9.7.1`（`gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`） |

MIUIX **没有 GitHub Release**，发布只在 Maven Central——不要去 GitHub Releases 找版本。
核实方法见 `references/verification.md`。

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
