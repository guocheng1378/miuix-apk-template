---
name: generate-miuix-app
description: 从零生成或改造一个 MIUIX（Compose Multiplatform + Kotlin）风格的 Android APK 应用——带悬浮液态玻璃底栏、miuix-nav 页面栈导航、大标题折叠 TopAppBar、下拉刷新、Coil 图集、miuix-preference 设置页、主题持久化与 edge-to-edge。当用户要求"生成 MIUIX 风格 app / 套壳 MIUIX / 液态玻璃底栏 / miuix 导航应用 / 用 miuix 搭建 Android 界面"时使用。
---

# 生成 MIUIX 风格 APK 应用

## 何时使用

- "生成一个 MIUIX 风格的 app" / "用 miuix 搭建 Android 界面" / "套壳 MIUIX"
- "液态玻璃底栏" / "悬浮玻璃导航栏" / "iOS 风液态玻璃"
- "miuix-nav 页面栈导航" / "大标题折叠 TopAppBar"
- 任何要求原生 Android 界面 + Release APK 产出，且点名 MIUIX 组件库的请求（配好签名 Secrets 才产出**已签名** APK，否则只能产出 unsigned release）

## 技术栈（CI 端到端编译验证过的组合，非推测）

| 项 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`miuix-ui` + `miuix-icons` + `miuix-blur` + `miuix-nav` + `miuix-preference` + `miuix-squircle`） |
| Coil | `3.6.1`（`coil-compose` 放 commonMain；`coil-network-okhttp` 放 androidMain） |
| kotlinx-serialization | `1.11.0` |
| compileSdk / targetSdk | `37` |
| minSdk | `24` |
| JDK（CI） | `21`（Zulu） |
| Gradle | `9.7.1`（`gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`） |

> **compileSdk 必须 37**：miuix `0.9.4-rc01` 的 AAR 声明 `minCompileSdk=37`，低于 37 会直接构建失败——这是最容易忽略的硬性前提。

> **版本核实方法**：`curl https://repo1.maven.org/maven2/top/yukonga/miuix/kmp/<module>/maven-metadata.xml` 看 `<latest>`。MIUIX 仓库是 github.com/yukonga/miuix，但**没有 GitHub Release**，发布只在 Maven Central，不要去 GitHub Releases 找。
> 任何 MIUIX API 改动前，先 `curl` 下载 `<module>-0.9.4-rc01-sources.jar` 解包核对真实签名，再写代码——本机常无 JDK/Gradle，只能靠 CI 验证。

## 推荐实现路径：派生式

若本机已有参考实现（如 `/root/.kimi-code/miuix-apk-template`），**优先以它为基线**，按用户需求改包名 / 应用名 / 主题色 / 页面，而不是从空白重写。若无基线，严格按下方"完整结构"从零生成。

## 完整项目结构

```
miuix-apk-template/
├── settings.gradle.kts
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties
├── .gitignore
├── shared/
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/<pkg>/
│       ├── App.kt                 # MiuixTheme + Scaffold + 导航 + 底栏接线 + 各页面
│       ├── Route.kt               # @Serializable 路由
│       ├── AppPrefs.kt            # 跨平台偏好接口
│       ├── ui/Theme.kt           # KeyColors / keyColorFor / isInDarkTheme
│       └── component/liquid/      # LiquidGlassNavigationBar（改编 Kyant0/AndroidLiquidGlass, Apache-2.0）
│           ├── LiquidGlassNavigationBar.kt
│           ├── CombinedBackdrop.kt
│           ├── Lens.kt
│           ├── Vibrancy.kt
│           └── InnerShadow.kt
│       └── component/animation/
│           ├── InteractiveHighlight.kt
│           └── DampedDragAnimation.kt
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/<pkg>/MainActivity.kt        # enableEdgeToEdge + 注入 AppPrefs
│       ├── kotlin/<pkg>/AndroidAppPrefs.kt     # SharedPreferences 实现
│       └── res/values|drawable|mipmap-anydpi-v26/...
└── .github/workflows/build-apk.yml
```

> 仓库**没有提交** `gradlew` 与 `gradle/wrapper/gradle-wrapper.jar`，只保留了 `gradle-wrapper.properties`（记录 Gradle `9.7.1`）。CI 靠 `gradle/actions/setup-gradle@v6` 提供 Gradle；本地构建需自备 Gradle 9.x + Android SDK，或自行补交 wrapper jar。

## 关键 API（MIUIX 0.9.4-rc01，已逐一核对 sources）

- `ThemeController(colorSchemeMode: ColorSchemeMode, keyColor: Color?)`；`MiuixTheme(controller)`
  - `ColorSchemeMode`：`System` / `Light` / `Dark` / `MonetSystem` / `MonetLight` / `MonetDark`
- `Scaffold(topBar/bottomBar/floatingActionButton/snackbarHost)`；`TopAppBar(title, largeTitle, scrollBehavior, navigationIcon)`
- 大标题折叠：`MiuixScrollBehavior()` 传给 `TopAppBar(scrollBehavior = ...)` 即可，miuix `Scaffold` 内部已接管滚动；**不要**手写 `Modifier.nestedScroll(scrollBehavior.nestedScroll.connection)`（miuix 的 `ScrollBehavior` 没有暴露 `nestedScroll.connection`，写了直接编译失败）
- `miuix-nav`：`rememberNavController<Route>(Route.Home)` + `NavDisplay { entry<Route.X> { ... } }`；`push/pop/replace`；`Route` 必须 `@Serializable sealed interface Route : NavKey`（闭式多态，无需 SerializersModule）
- `miuix-blur`：`rememberLayerBackdrop()`、`Modifier.textureBlur(backdrop, shape, blurRadius, colors)`、`isRuntimeShaderSupported()`（Android 12+；不支持时 `backdrop==null`，需降级）
- `miuix-preference`：`RadioButtonPreference(title, selected, onClick)`、`SwitchPreference(checked, onCheckedChange, title)`（均基于 `BasicComponent`，自带 `Role.RadioButton`/`Role.Switch`）
- `miuix-squircle`：`Modifier.squircleSurface(color, cornerRadius)` / `squircleBackground` / `squircleBorder`（不支持 RuntimeShader 时回退 `RoundedCornerShape`）
- `OverlayBottomSheet(show, title, onDismissRequest)`、`PullToRefresh(isRefreshing, onRefresh, pullToRefreshState, topAppBarScrollBehavior)` + `rememberPullToRefreshState()`
- `BasicComponent(title, summary, modifier, startAction, endActions, onClick)`、`SmallTitle`、`Card`、`Switch`、`Slider`、`Checkbox(state=ToggleableState, onClick)`、`RadioButton(selected, onClick)`、`FloatingActionButton`、`SnackbarHost` / `SnackbarHostState`、`MiuixIcons`（extended：Home/Image/Settings/Back…）
- Coil：`coil3.compose.SubcomposeAsyncImage(model, contentDescription, modifier, contentScale, loading = { ... }, error = { ... })`（commonMain）；**网络图必须** `coil-network-okhttp` 在 androidMain + `INTERNET` 权限
- 液态玻璃底栏 `IosLiquidGlassNavigationBar(items, selectedIndex, onItemClick, backdrop, isBlurActive)` 来自改编 Kyant0/AndroidLiquidGlass（Apache-2.0），组合 LayerBackdrop + textureBlur + Highlight + 设备倾斜传感器

## 依赖配置要点（shared/build.gradle.kts）

```kotlin
plugins {
    id("com.android.kotlin.multiplatform.library") version "9.3.2"  // AGP 9 的 KMP 库专用插件
    id("org.jetbrains.kotlin.multiplatform") version "2.4.10"
    id("org.jetbrains.compose") version "1.12.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.10"
}

kotlin {
    // KMP 新 DSL：Android 目标内联在 kotlin { android { ... } }，没有顶层 android { } 块，也不调用 androidTarget()
    android {
        namespace = "<pkg>.shared"
        compileSdk = 37   // miuix 0.9.4-rc01 AAR 要求 minCompileSdk=37
        minSdk = 24
        androidResources { enable = true }  // 新插件默认关闭资源处理
    }
    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime); implementation(compose.foundation); implementation(compose.ui)
            implementation("top.yukonga.miuix.kmp:miuix-ui:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-icons:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-blur:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-nav:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-preference:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-squircle:0.9.4-rc01")
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-core:1.11.0")
            implementation("io.coil-kt.coil3:coil-compose:3.6.1")
        }
        androidMain.dependencies {
            implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.1")  // 只能放 androidMain
        }
    }
}
```

- 必须插件：`com.android.kotlin.multiplatform.library`、`org.jetbrains.kotlin.multiplatform`、`org.jetbrains.compose`、`org.jetbrains.kotlin.plugin.compose`、`org.jetbrains.kotlin.plugin.serialization`。**不能**用 `com.android.library`（AGP 9 内置 Kotlin 后与 KMP 扩展名冲突）
- `coil-network-okhttp` **只能放 androidMain**（commonMain 无该变体），否则解析失败
- `app/build.gradle.kts`：`com.android.application` + `org.jetbrains.kotlin.plugin.compose`；**不含** `org.jetbrains.kotlin.android`（AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报 `Remove the 'org.jetbrains.kotlin.android' plugin`）；依赖 `project(":shared")` + `androidx.activity:activity-compose:1.13.0`（提供 `enableEdgeToEdge`）；签名配置用 `signingProp(name)` helper：优先读环境变量，回退 `local.properties`

## gradle.properties（最终形，只有这 5 行）

```properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
org.gradle.caching=true
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
```

不要加 `android.newDsl=false`——shared 迁移到 KMP 新 DSL 后该行已删除。

## 主题持久化（跨重启保留）

- `commonMain` 定义接口 `interface AppPrefs { var themeMode: Int; var keyColorIndex: Int; var notificationsEnabled: Boolean }`
- `app` 模块用 `class SharedPreferencesAppPrefs(context) : AppPrefs`（同步读写，无需挂起）
- `App(prefs: AppPrefs)` 初始化读 prefs，运行中写回 prefs；`themeMode` 约定 `0=System 1=Light 2=Dark 3=MonetSystem`

## Android 侧要点

- `MainActivity.onCreate`：`enableEdgeToEdge()` + `setContent { App(prefs = SharedPreferencesAppPrefs(this)) }`
- `AndroidManifest.xml`：
  - `<uses-permission android:name="android.permission.INTERNET" />`（Coil 网络图）
  - `android:exported="true"`（targetSdk 31+ 必须）
  - `<uses-sdk tools:overrideLibrary="top.yukonga.miuix.kmp.blur" />`
  - LAUNCHER `intent-filter`
- 图标：`mipmap-anydpi-v26/ic_launcher.xml`（adaptive-icon）→ `res/values/colors.xml` 的 `ic_launcher_background` + `res/drawable/ic_launcher_foreground.xml`

## CI（GitHub Actions，.github/workflows/build-apk.yml）

- 触发：`on.push.tags: ["v*"]` + `workflow_dispatch`
- 步骤：checkout → setup-java Zulu 21 → `gradle/actions/setup-gradle@v6` → decode signing key（Secrets）→ `gradle :app:assembleRelease --no-daemon` → upload-artifact → tag 时 `softprops/action-gh-release`
- **构建命令是 `gradle`，不是 `./gradlew`**：仓库未提交 wrapper jar，由 setup-gradle 提供与 AGP 9.x 匹配的 Gradle 9.x 并在 PATH 上。**不要**在 workflow 里现场 `gradle wrapper --gradle-version 8.13`——那会造成版本错配
- Secrets：`SIGNING_KEY`（base64 keystore）、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`
- 判断写在 shell step 内部 `if [ -n "$SIGNING_KEY" ]`：GitHub 的 `secrets.*` 不能出现在 step 级 `if:` 里，否则整个 workflow 会被解析成 0 个 job
- **未配置 Secrets 时产物是 `app-release-unsigned.apk`**（不是 debug 签名的可安装包），需自行 `apksigner` 对齐签名后才能安装/发布；配齐 Secrets 才产出已签名 Release APK
- 打 `v*` tag 时 workflow 会额外创建 GitHub Release 并附上 APK
- **Action 版本必须真实存在**：用 `curl https://api.github.com/repos/<owner>/<action>/releases/latest` 核实（到 2026 年 checkout/setup-java/setup-gradle/upload-artifact 已是 v6/v7，不要臆测）
- 本地构建需自备 Gradle 9.x + Android SDK（或补交 `gradlew` 与 `gradle/wrapper/gradle-wrapper.jar`）

## 标准检测流程（交付前必做）

1. **静态检测**：资源完整性、Manifest（权限/exported/intent-filter）、Gradle 版本一致、依赖版本、CI Action 版本真实性、代码一致性（未使用 import / 类型匹配 / 稳定 key）
2. **构建**：`gradle :app:assembleRelease --no-daemon`（本地无 wrapper 时；CI 同命令）
3. **二进制检测**：`aapt2 dump badging`（包名/权限/minSdk/图标）、`apkanalyzer`（大小/DEX/依赖）、签名方案 v1/v2/v3、危险权限核对（预期仅 `INTERNET`）
4. **运行时冒烟**：`adb install` + 四 tab 导航、下拉刷新、左滑删除+撤销、主题/主题色重启持久化、详情页回显图片

> 本机无 JDK/Gradle/SDK 时，1 可做、2–4 需 GitHub Actions 或本地 SDK。推送前必须确认环境有 GitHub 凭证（PAT/ssh key），否则无法触发 CI。

## 已知坑（务必规避）

- `key(i) { ... }` 稳定 key 需 `import androidx.compose.runtime.key`，否则编译失败
- 液态玻璃依赖 `RuntimeShader`（Android 12+），不支持时 `backdrop==null`，应降级为纯色/squircle，且 UI 给出提示
- `miuix-preference` 的 `RadioButtonPreference` 默认 `radioButtonLocation = Start`
- `ui/Theme.kt` 的 `AppTheme`/`LocalColorMode` 是死代码，但 `isInDarkTheme` 被液态底栏依赖——删 Theme.kt 时保留它
- 列表删除用稳定 id（`filter { it != id }`），不要按值删 `items - i`
- 左滑删除需自写 foundation `draggable`（MIUIX 0.9.4-rc01 无内置 SwipeToDismiss）
- 图片页 `PullToRefresh` 包裹 `LazyVerticalGrid` 时，滚动仍交给 miuix `Scaffold`，**不要**给 grid 挂 `nestedScroll(scrollBehavior.nestedScroll.connection)`
- `AsyncImage` 改用 `SubcomposeAsyncImage` 才有 `loading`/`error` 插槽
- 详情页回显图片：与图片页共用 `seed`（`picsum.photos/seed/$id/...`），无需改 `Route`
- 作用域成员不能顶层 import：`androidx.compose.foundation.layout.weight`、`...matchParentSize` 这类要删掉 import，靠接收者作用域使用
- Coil 3 的组件在 `coil3.compose.*`（例如 `coil3.compose.SubcomposeAsyncImage`），不是 `androidx.compose.*`
- `Icon` 用 `top.yukonga.miuix.kmp.basic.Icon`，不是 `androidx.compose.foundation.Icon`
- miuix 的 `ScrollBehavior` **没有**暴露 `nestedScroll.connection`，不要手写 `.nestedScroll(scrollBehavior.nestedScroll.connection)`——miuix `Scaffold` 内部已接管滚动（手动连接会编译失败）
- miuix AAR 要求 compileSdk 37，这是最容易忽略的硬性前提
- GitHub PAT 一旦明文出现在对话里，交付后立即撤销

## 安全与凭证

- 生成仓库、打 tag、触发 CI 需要 GitHub 凭证。只在用户明确提供时用于一次性 `git remote add` + `push`，push 后立即 `git remote set-url origin <不含token的URL>` 清理 `.git/config`
- 永远不要回显用户提供的 token
- 用户提供的 PAT 用完即建议其在 GitHub 撤销
