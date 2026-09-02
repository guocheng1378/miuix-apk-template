# 核验方法与交付前检测

## 四级核验法

任何「某个 API 长什么样 / 某个版本存不存在」的判断，按这个顺序往上走，
**下一级推翻上一级**：

1. **文档**——只用它了解某个模块**是干什么的**、概念边界。不要从文档抄签名，
   文档版本落后于源码是常态。
2. **Demo**——看某个 API 的**最小调用形态**（需要哪些必填参数、最简接线）。
3. **Example**——看多个 API 的**完整组合方式**（真实页面怎么把导航 + 主题 + 底栏拼起来）。
4. **对应版本的源码**——最终裁决参数与行为。

第 4 步有个前提：**先确定目标项目实际用的版本号，再挑该版本对应的上游 tag/commit 去看**。
本 skill 里的快照（`miuix-api.md`）只对 `0.9.4-rc01` 有效；若目标项目版本不同，
把它当 fallback 并在结论里**明确标注版本不匹配**，不要拿快照冒充目标版本的事实。

## 无 JDK 环境下的实测核验手段

这些命令我都真跑过，输出即证据。注意 `api.github.com` 匿名配额只有 60/小时，
打满后返回 403 且 `x-ratelimit-remaining: 0`——下面的写法尽量绕开它。

### 版本存在性与最新值（Maven metadata）

```bash
curl -s https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/<module>/maven-metadata.xml
```

看 `<latest>` 与 `<versions>`。AGP 用 `dl.google.com` 的 metadata：

```bash
curl -s https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml
```

实测（2026-09）：miuix 各模块 `<latest>0.9.4-rc01`（lastUpdated 20260813）；
`miuix-nav` **只有** `0.9.4-rc01` 一个版本；`coil-compose` 最新 `3.6.1`；
`kotlinx-serialization-core` 最新 `1.11.0`；AGP 有 `9.3.2`（也有 `9.4.0`）；
Kotlin gradle plugin 有 `2.4.10`。

MIUIX **没有 GitHub Release**，发布只在 Maven Central——不要去 GitHub Releases 找。

### AAR 里挖 minSdk / minCompileSdk（最有价值的一招）

`compileSdk` 与 `minSdk` 的真实要求写在 AAR 内部，文档不会告诉你：

```bash
cd "$(mktemp -d)"
curl -sSLO https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/miuix-blur-android/0.9.4-rc01/miuix-blur-android-0.9.4-rc01.aar
unzip -o -q miuix-blur-android-0.9.4-rc01.aar
grep -o 'minSdkVersion="[0-9]*"' AndroidManifest.xml
grep minCompileSdk aar-metadata.properties
```

实测结果：

| 模块 | `minSdkVersion` | `minCompileSdk` |
|---|---|---|
| `miuix-blur-android` | **33** | 37 |
| `miuix-ui-android` | 24 | 37 |
| `miuix-nav-android` | 24 | 37 |

→ 「compileSdk 必须 37」「blur 在 Android 要求 minSdk 33」两条硬约束由此实证。

### 上游仓库真实地址（POM 比 README 可靠）

```bash
curl -s https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/miuix-ui/0.9.4-rc01/miuix-ui-0.9.4-rc01.pom \
  | grep -Eo '<(url|scm)>[^<]*|<connection>[^<]*'
```

POM 的 `<url>` / `<scm>` 指向 **`https://github.com/compose-miuix-ui/miuix`**，
license `Apache-2.0`。Maven **groupId 仍是 `top.yukonga.miuix.kmp`**（坐标不变），
但源码 org 已迁移——写引用时用 `compose-miuix-ui/miuix`。

### API 签名核对（sources jar）

```bash
curl -sSLO https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/miuix-ui/0.9.4-rc01/miuix-ui-0.9.4-rc01-sources.jar
unzip -o -q miuix-ui-0.9.4-rc01-sources.jar -d src
grep -rn "fun IosLiquidGlassNavigationBar\|fun textureBlur" src
```

### 绕开 GitHub API 配额取仓库元信息

```bash
curl -sS -H "User-Agent: Mozilla/5.0" https://github.com/<owner>/<repo> \
  | grep -o '"stargazerCount":[0-9]*'
```

许可证直接取文件：`curl -s https://raw.githubusercontent.com/<o>/<r>/HEAD/<path>`
（404 即无该文件）。

## 交付前检测清单

### 1. 静态检测（本机就能做，无 JDK 也有效）

先跑脚本：

```bash
bash scripts/preflight.sh [repo-root]
```

它检查 SKILL.md 里那 11 条不可协商项中能静态 grep 出来的部分，逐项 PASS/FAIL。
其中 `[模板镜像]` 一项会比对 `assets/workflow-build-apk.yml` 与仓库权威 workflow 的
非注释行：不一致时报 WARN（不挡退出码），处理方式是**改镜像不是改仓库那份**——
仓库里的 `.github/workflows/build-apk.yml` 才是权威，模板落后就会把旧版本抄回新项目。

在此之上人工过一遍：

- 资源完整性（`res/` 引用的 drawable/color/mipmap 都存在）
- Manifest：权限、`android:exported`、`intent-filter`、`tools:overrideLibrary`
- Gradle 版本一致性：AGP / Kotlin / Compose / Gradle wrapper 四者互相兼容
- 依赖版本真实存在（用上面的 metadata 法核）
- CI Action 版本真实存在（用 `releases/latest` 重定向法核）
- 代码一致性：未使用 import、类型匹配、`key(i)` 有稳定 key

### 2. 构建

```
gradle :app:assembleRelease --no-daemon
```

本机无 JDK/Gradle/SDK 时**做不了**，交给 GitHub Actions。

### 3. 二进制检测

- `aapt2 dump badging`：包名 / 权限 / minSdk / 图标
- `apkanalyzer`：体积 / DEX / 依赖
- 签名方案 v1/v2/v3 是否齐
- 危险权限核对（本模板预期**仅** `INTERNET`）

需要 Android SDK build-tools，本机通常没有 → CI 或本地 SDK 环境做。

### 4. 运行时冒烟

`adb install` 后过：四 tab 导航、下拉刷新、左滑删除 + 撤销、
主题/主题色**重启后**仍保留、详情页回显图片。

需要真机/模拟器，本机做不了。

## 报告纪律

写结论时把「实测」和「依据文档/源码推断」分开标注。本机没有 JDK 时，
gradle 构建、CI 实跑、签名验证、`claude plugin validate` 都**无法实跑**——
必须如实写成未验证，不能因为「配置看起来对」就报成通过。
