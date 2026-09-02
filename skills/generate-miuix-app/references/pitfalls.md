# 坑库

按失败发生的层次分组。撞错误先按类别查，再按关键字搜本文件。

## A. 编译期（Kotlin / Compose）

| 症状 | 原因与解法 |
|---|---|
| `Unresolved reference: key` | `key(i) { ... }` 的稳定 key 需 `import androidx.compose.runtime.key` |
| `Unresolved reference: weight` / `matchParentSize` | **作用域成员不能顶层 import**：`androidx.compose.foundation.layout.weight`、`...matchParentSize` 这类要删掉 import，靠接收者作用域使用 |
| `Unresolved reference: Icon` 或解析到错的对象 | `Icon` 用 `top.yukonga.miuix.kmp.basic.Icon`，**不是** `androidx.compose.foundation.Icon` |
| `AsyncImage` 没有 `loading` / `error` 参数 | 改用 `SubcomposeAsyncImage` |
| Coil 组件全部 unresolved | Coil 3 在 `coil3.compose.*`（如 `coil3.compose.SubcomposeAsyncImage`），不是 `androidx.compose.*` |
| extended 图标 unresolved | `MiuixIcons.extended.Home/Image/Settings/Back` 要单独 import：`top.yukonga.miuix.kmp.icon.extended.Home` |
| 手写 `.nestedScroll(scrollBehavior.nestedScroll.connection)` 编译失败 | miuix 的 `ScrollBehavior` **没有**暴露 `nestedScroll.connection`。miuix `Scaffold` 内部已接管滚动，删掉手写连接即可 |
| 删 `ui/Theme.kt` 后底栏编译失败 | `AppTheme` / `LocalColorMode` 确实是死代码，但 **`isInDarkTheme()` 被液态底栏依赖**——删文件时保留它 |

## B. 依赖与 Gradle 配置

| 症状 | 原因与解法 |
|---|---|
| 构建失败，报 compileSdk 相关 | miuix `0.9.4-rc01` AAR 声明 `minCompileSdk=37`（解包实测）。**`compileSdk = 37` 是硬性前提**，最容易忽略 |
| `Remove the 'org.jetbrains.kotlin.android' plugin` | AGP 9 已内置 Kotlin 支持。`app` 模块只留 `com.android.application` + `org.jetbrains.kotlin.plugin.compose` |
| shared 模块扩展名冲突 / DSL 报错 | 用 `com.android.kotlin.multiplatform.library`，**不能**用 `com.android.library` |
| `androidTarget()` unresolved 或找不到 `android {}` 块 | KMP 新 DSL：Android 目标内联在 `kotlin { android { ... } }`，没有顶层 `android {}`，不调用 `androidTarget()` |
| shared 里 `res/` 不生效 | 新插件默认关闭资源处理，需 `androidResources { enable = true }` |
| `coil-network-okhttp` 解析失败 | **只能放 `androidMain`**，commonMain 无该变体 |
| 想降 miuix-nav 版本但找不到 | `miuix-nav` 在 Maven Central 上**只有 `0.9.4-rc01` 一个版本**（实测 metadata），没有回退空间 |
| 找不到 miuix 的 GitHub Release | miuix **不发 GitHub Release**，只在 Maven Central。别去 Releases 页找 |
| 低版本真机装上后模糊相关崩溃 | blur 要求 `minSdk 33`，工程 `minSdk 24` 靠 `tools:overrideLibrary` 放行。**必须**保留 `isRuntimeShaderSupported()` 降级分支（`backdrop = null` → 纯色/squircle + UI 提示） |
| `local.properties` 里有 `android.newDsl=false` | 残留行。shared 迁移到新 DSL 后该配置已删除，留着会误导（`gradle.properties` 最终只有 5 行） |
| 找不到根 `build.gradle.kts` 以为仓库坏了 | 本模板**就没有**根构建文件，配置在 `settings.gradle.kts` + 两个模块里。别新建 |

## C. CI / Actions

| 症状 | 原因与解法 |
|---|---|
| Release 创建步骤 403 `Resource not accessible by integration` | workflow 顶层缺 `permissions: contents: write`（缺省只有 read）。本仓库提交 `f2d4377` 就是修这个 |
| push 了 workflow 但 Actions 里显示 **0 个 job**，静默不跑 | `secrets.*` 出现在 step 级 `if:` 里。判断要写进 shell step 内部 `if [ -n "$SIGNING_KEY" ]` |
| `./gradlew: No such file or directory` | 仓库未提交 `gradlew` 与 wrapper jar，只留 `gradle-wrapper.properties`。CI 用 `gradle`（由 setup-gradle 提供） |
| Gradle/AGP 版本错配报错 | **不要**在 workflow 里现场 `gradle wrapper --gradle-version 8.x` |
| Action 版本不存在、workflow 起不来 | 用 `curl -sSL -o /dev/null -w '%{redirect_url}\n' https://github.com/<owner>/<action>/releases/latest` 核实。2026 年 `checkout`/`upload-artifact` 已到 v7，`setup-java`/`setup-gradle` 到 v6 |
| Release 页上的 APK 装不上 | 未配 Secrets 时产物是 `app-release-unsigned.apk`，不是 debug 签名的可安装包。加 Verify 步骤：文件名含 `unsigned` 就 `exit 1`，再 `apksigner verify` |
| keystore 疑似泄露 | public 仓库里把 keystore 当 artifact 上传 = 任何持 token 者可下载。只走 Secrets |
| `api.github.com` 突然 403 | 匿名配额 60/小时打满（`x-ratelimit-remaining: 0`）。改用 `raw.githubusercontent.com` 取文件、抓 HTML 里的 JSON 字段 |

## D. 签名

| 症状 | 原因与解法 |
|---|---|
| AGP 读 keystore 失败 | openssl 走的是 PKCS12，signingConfig **必须**显式 `storeType = "PKCS12"`，否则按默认 JKS 读 |
| Secrets 写入运行期报参数/长度错误 | PyNaCl 用成了 `Box`。GitHub 需要 **`public.SealedBox`**（只需对方公钥） |
| Secrets PUT 返回 204 以为失败 | 覆盖已存在的 secret 返回 **204**，首次创建返回 **201**，两者都算成功 |
| `base64` 解出来的 keystore 损坏 | Secret 值必须 `base64 -w0`（单行无换行）。多行会被 CI 的 `base64 -d` 前的处理破坏 |
| 换机后无法覆盖升级 | keystore/口令丢了。同一 `applicationId` 再也无法覆盖安装到已装用户机上，只能换包名重发。**异地备份** |

## E. 文档漂移（写引用前必读）

| 常见错误说法 | 实际 | 依据 |
|---|---|---|
| 「MIUIX 仓库是 `github.com/yukonga/miuix`」 | 源码 org 已迁到 **`github.com/compose-miuix-ui/miuix`**；Maven groupId 仍是 `top.yukonga.miuix.kmp` 不变 | `miuix-ui-0.9.4-rc01.pom` 的 `<url>`/`<scm>`。`github.com/yukonga/miuix` 返回 200 是因为重定向 |
| 「文档站 `miuix.terres.cn` / `books.miuix.terres.cn`」 | **DNS 解析失败**（实测），不要引用这个域名 | `curl` 直接失败 |
| 「miuix 有 GitHub Release 可跟版本」 | 没有，只在 Maven Central 发布 | 实测 |
| 「本仓库有 LICENSE / 可以标 SPDX」 | 仓库**没有** LICENSE 文件，凭空写许可证就是编造 | 实测文件不存在 |

## F. 行为细节（不报错但结果不对）

- `keyColorFor(index)`：**`index <= 0` 返回 `null`**（表示「跟随默认 `0xFF3482FF`」），
  否则取 `KeyColors[index-1]`。把 `0` 当「第一个色」是 off-by-one。
- `themeMode` 映射：`1=Light 2=Dark 3=MonetSystem`，**其余（含 0）落 `System`**。
- `RadioButtonPreference` 默认 `radioButtonLocation = Start`（不是 end）。
- 底栏 textureBlur 实测参数 `blurRadius = 25f` +
  `BlurDefaults.blurColors(blendColors = listOf(BlendColorEntry(surface.copy(alpha = 0.8f))))`；
  `LiquidButton` 是 `blurRadius = 18f`。
- 列表删除用稳定 id（`filter { it != id }`），**不要**按值删 `items - i`
  （重复值会误删）。
- 左滑删除需自写 foundation `draggable`——MIUIX 0.9.4-rc01 **无**内置 SwipeToDismiss。
- 详情页回显图片：与图片页共用 `seed`（`picsum.photos/seed/$id/...`），无需改 `Route`。
- release 的 `isMinifyEnabled = false`。开混淆前要先补 proguard 规则（miuix/Coil 有反射点），
  否则表现为运行期 `ClassNotFoundException` 而不是编译错误。

## G. 凭证

- 用户提供的 PAT 明文出现在对话里 → 交付后立即建议撤销。
- 一次性 `git remote add` + `push` 之后，必须
  `git remote set-url origin <不含 token 的 URL>` 清理 `.git/config`。
- 永远不要回显 token（包括日志、错误输出、报告里）。
