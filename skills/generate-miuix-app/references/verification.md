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

下面每条命令都真跑过，输出即证据。`api.github.com` 匿名配额只有 60/小时，
打满后返回 403 且 `x-ratelimit-remaining: 0`——所以这些手段全部走 Maven Central
与 `dl.google.com`，不碰 API 配额。Action 版本的核实法在 `ci-workflow.md`。

### 版本存在性与最新值（Maven metadata）

```bash
curl -s https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/<module>/maven-metadata.xml
```

看 `<latest>` / `<release>` / `<versions>`。AGP 用 `dl.google.com` 的 metadata：

```bash
curl -s https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/maven-metadata.xml
```

实测（2026-09-02）：

- miuix 各模块 `<latest>0.9.4-rc01`，`miuix-ui` 的 `<lastUpdated>20260813160507`。
- `<versions>` 逐模块不同：`miuix-ui` / `miuix-blur` / `miuix-preference` 是
  `0.9.0…0.9.3, 0.9.4-rc01`；`miuix-squircle` 从 `0.9.2` 起；`miuix-icons` 另有
  一整串 `0.8.x`；**`miuix-nav` 只有 `0.9.4-rc01` 一个版本**（无回退空间）。
- `coil-compose` 最新 `3.6.1`；`kotlinx-serialization-core` 最新 `1.11.0`。
- AGP 存在 `9.3.2`（模板所用）与更新的 `9.4.0`。
- `kotlin-gradle-plugin` 存在稳定版 `2.4.10`（模板所用），`<latest>` 是
  `2.4.20-RC3`——**预发布版本会占掉 `<latest>`**，取「最新稳定版」要回 `<versions>`
  里挑，别直接抄 `<latest>`。

MIUIX **有** GitHub Releases（实测 `compose-miuix-ui/miuix`：`v0.9.4-rc01`、`v0.9.3`、
`v0.9.2`、`v0.9.1`、`v0.9.0`、`v0.8.8`…）。但注意 **rc 版标的是 `prerelease: true`**，
而 `/releases/latest` 端点按设计排除 prerelease——所以它只回 `v0.9.3`，
据此断言「最新是 0.9.3」或「miuix 不发 Release」都是错的。
判断版本可用性一律以 Maven Central 的 `maven-metadata.xml` 为准。

### AAR 里挖 minSdk / minCompileSdk（最有价值的一招）

`compileSdk` 与 `minSdk` 的真实要求写在 AAR 内部，文档不会告诉你：

```bash
cd "$(mktemp -d)"
curl -sSLO https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/miuix-blur-android/0.9.4-rc01/miuix-blur-android-0.9.4-rc01.aar
unzip -o -q miuix-blur-android-0.9.4-rc01.aar
grep -o 'minSdkVersion="[0-9]*"' AndroidManifest.xml
# 注意元数据文件不在 AAR 根目录，在 META-INF 深处：
grep -r minCompileSdk META-INF/com/android/build/gradle/aar-metadata.properties
```

实测结果（2026-09-02 重新解包核对）：

| 模块 | `minSdkVersion` | `minCompileSdk` |
|---|---|---|
| `miuix-blur-android` | **33** | 37 |
| `miuix-ui-android` | 24 | 37 |
| `miuix-nav-android` | 24 | 37 |

三个模块的 `aar-metadata.properties` 里 `minCompileSdk` 全是 **37**，另有
`minAndroidGradlePluginVersion=1.0.0`（即 AGP 版本不是瓶颈）。

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

坐标形如 `https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/<module>/<version>/<module>-<version>-sources.jar`：

```bash
cd "$(mktemp -d)"
for m in miuix-core miuix-ui miuix-icons miuix-blur miuix-nav miuix-squircle miuix-preference; do
  curl -sSLO "https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/$m/0.9.4-rc01/$m-0.9.4-rc01-sources.jar"
  unzip -o -q "$m-0.9.4-rc01-sources.jar" -d "src/$m"
done
grep -rn "fun textureBlur" src/miuix-blur
grep -rn "data class NavigationItem" src/miuix-ui
```

**七个模块都要下**，少下几个就会得出「某个 API 不存在」的错误结论——
`MiuixIcons` 在 `miuix-core`、156 个扩展图标在 `miuix-icons`、squircle 在
`miuix-squircle`，这三条以前被漏掉过。

sources jar 里只有 `<module>/commonMain/...` 与 `skikoMain`，包路径就是 import 路径，
例如 blur 在 `miuix-blur/commonMain/top/yukonga/miuix/kmp/blur/TextureEffect.kt`。
另注意 `<module>-android` 那个 artifact 也有 sources jar，它的内容是
`androidMain` **加上又重复一遍** `commonMain`——两种 jar 混在一个目录树里数文件会重复计数
（本次实测：7 个纯 sources jar 共 325 个 `.kt`，其中 `commonMain` 316 个；
把 `-android` 的重复副本也算进去就会明显偏多）。统计一律用
`find . -name '*.kt' -not -path '*-android/*'`。

**grep 无命中即证否**——这一条用来判定「某个组件到底是不是库提供的」。
本模板的液态玻璃底栏 `IosLiquidGlassNavigationBar` 在全部 7 个模块的 sources jar 里
**一处都搜不到**，它是模板自己的代码
（`shared/src/commonMain/kotlin/component/liquid/LiquidGlassNavigationBar.kt:195`，
改编自 Kyant0/AndroidLiquidGlass）。派生新 app 时这块必须自己带，
不能指望依赖里有。

## 交付前检测清单

### 1. 静态检测（本机就能做，无 JDK 也有效）

先跑脚本：

```bash
bash scripts/preflight.sh [repo-root]
```

它检查 SKILL.md「不可协商项」清单中能静态 grep 出来的部分（清单会增删，所以这里
不写条数），按组逐项 PASS/FAIL/WARN，任一 FAIL 退出码 1。**组和 PASS 的条数会随
脚本增补不断变化，不要在文档或 PR 描述里引用具体数字**——以你这一次运行的输出
为准；要数分组就 `bash scripts/preflight.sh . 2>&1 | grep -c '^\['`。
其中 `[模板镜像]` 一项会比对
`assets/workflow-build-apk.yml` 与仓库权威 workflow 的非注释非空行：不一致时报
WARN（不挡退出码），处理方式是**改镜像不是改仓库那份**——仓库里的
`.github/workflows/build-apk.yml` 才是权威，模板落后就会把旧版本抄回新项目。

在此之上人工过一遍：

- 资源完整性（`res/` 引用的 drawable/color/mipmap 都存在）
- Manifest：权限、`android:exported`、`intent-filter`、`tools:overrideLibrary`
- Gradle 版本一致性：AGP / Kotlin / Compose / Gradle wrapper 四者互相兼容
- 依赖版本真实存在（用上面的 metadata 法核）
- CI Action 版本真实存在（用 `releases/latest` 重定向法核，见 `ci-workflow.md`）
- 代码一致性：未使用 import、类型匹配、`key(i)` 有稳定 key

### 2. 构建 / 签名 / 冒烟（交给 CI）

```
gradle :app:assembleRelease --no-daemon
```

本机无 JDK/Gradle/SDK 时**做不了**。仓库现有三套 workflow 覆盖构建、
JVM 截图回归、依赖审查，各自触发条件与坑见 `ci-workflow.md`。

### 3. 二进制检测

- `aapt2 dump badging`：包名 / 权限 / minSdk / 图标
- `apkanalyzer`：体积 / DEX / 依赖
- 签名方案 v1/v2/v3 是否齐
- 危险权限核对（本模板预期**仅** `INTERNET`）

需要 Android SDK build-tools，本机通常没有 → CI 或本地 SDK 环境做。

### 4. 运行时冒烟

`adb install` 后过：三个顶层 tab（首页 / 图片 / 设置）导航 + 详情页 push/pop、
下拉刷新、左滑删除 + 撤销、主题/主题色**重启后**仍保留、详情页回显图片。

需要真机/模拟器，本机做不了 → `build-apk.yml` 的 `smoke` job。

## 报告纪律

写结论时把「实测」和「依据文档/源码推断」分开标注。本机没有 JDK 时，
gradle 构建、CI 实跑、签名验证、`claude plugin validate` 都**无法实跑**——
必须如实写成未验证，不能因为「配置看起来对」就报成通过。
