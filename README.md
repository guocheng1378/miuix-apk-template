# MIUIX APK 模板（Compose Multiplatform）

用 **MIUIX 组件库**（`top.yukonga.miuix.kmp:miuix-ui`）搭建原生 Android 界面并产出 Release APK 的通用脚手架：**配好签名 Secrets 才产出已签名 APK**，未配置时产出 `app-release-unsigned.apk`（需自行用 `apksigner` 对齐并签名后才能安装/发布）。

全流程托管在 GitHub：把仓库推上去 →（可选）配置 Secrets → 打 `v*` tag（或手动触发）→ GitHub Actions 自动编译（配了密钥则同时签名）→ 产物为 APK（可下载 / 打 tag 时自动建 Release）。

> 本机**无需**安装 JDK / Android SDK；构建与签名全部在 GitHub Actions（自带 JDK 21 + Android SDK，并由 `setup-gradle` 提供 Gradle）完成。

## 技术栈（CI 端到端编译验证通过的组合）

| 组件 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`miuix-ui` + `miuix-icons` + `miuix-blur` + `miuix-nav` + `miuix-preference` + `miuix-squircle`） |
| Coil | `3.6.1`（`coil-compose` common + `coil-network-okhttp` android） |
| kotlinx-serialization | `1.11.0` |
| compileSdk / targetSdk | `37` |
| minSdk | `24` |
| JDK（CI） | `21`（Zulu） |
| Gradle | `9.7.1`（`gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`） |

> **compileSdk 必须是 37**：`miuix 0.9.4-rc01` 的 AAR 声明 `minCompileSdk=37`，低于 37 会直接构建失败。这是最容易忽略的硬性前提。

## 工程结构

```
miuix-apk-template/
├── settings.gradle.kts
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties   # 只提交 properties；gradlew 与 wrapper jar 未入库
├── shared/                         # KMP 库：commonMain 放 Compose UI
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/top/yukonga/miuixapptemplate/
│       ├── App.kt                  # 页面 + 导航
│       └── Route.kt                # @Serializable 路由定义
├── app/                            # 纯 Android 应用模块
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/.../MainActivity.kt
│       └── res/...                 # 图标、主题、字符串
├── skills/generate-miuix-app/      # 自动生成同类 App 的 skill
└── .github/workflows/build-apk.yml # 自动构建 + 签名
```

UI 写在 `shared/src/commonMain/kotlin/top/yukonga/miuixapptemplate/App.kt`，
用 MIUIX 组件（`TopAppBar` / `Scaffold` / `Card` / `Switch` / `Slider` / `Button` / `Text`）+ `MiuixTheme` 主题。
把这段 Composable 换成你自己的界面即可。

## 本地构建（可选，需本机有 JDK 21 + Android SDK + Gradle 9.x）

仓库**没有提交** `gradlew` 和 `gradle/wrapper/gradle-wrapper.jar`（只有 `gradle-wrapper.properties`），
本地构建要么自行准备与 AGP 9.x 匹配的 Gradle 9.x，要么补交 wrapper jar。

```bash
gradle :app:assembleRelease
# 未提供密钥：app/build/outputs/apk/release/app-release-unsigned.apk（unsigned，不能直接安装）
# 提供密钥：  app/build/outputs/apk/release/app-release.apk
```

本地密钥走 `local.properties`（`KEYSTORE_PATH` / `KEYSTORE_PASS` / `KEY_ALIAS` / `KEY_PASSWORD`），
同名环境变量优先级更高。

## GitHub Actions 自动构建 + 签名

### 1. 生成签名密钥（只需一次）

```bash
keytool -genkeypair -v \
  -keystore release.keystore -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mykey

# 转成单行 base64，后面要填进 Secret
base64 -w0 release.keystore > keystore.b64
cat keystore.b64
```

### 2. 在仓库配置 Secrets

`Settings → Secrets and variables → Actions → New repository secret`：

| Secret | 内容 |
|---|---|
| `SIGNING_KEY` | `keystore.b64` 的全部文本（base64） |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | `mykey`（上面的 alias） |
| `KEY_PASSWORD` | 密钥密码 |

> 不配置 Secrets 也能构建，但产物是 **`app-release-unsigned.apk`**——AGP 在没有 signingConfig 时根本不签名，**不会**回退成 debug 签名的可安装包。这种 APK 要安装/上架，需自行 `zipalign` + `apksigner sign`。

### 3. 构建命令与签名判定（真实形态）

- CI 用 `gradle/actions/setup-gradle@v6` 提供与 AGP 9.x 匹配的 Gradle 9.x（已在 PATH 上），构建命令是 `gradle :app:assembleRelease --no-daemon`，**不是** `./gradlew ...`（仓库未提交 wrapper）。
- 不要在 workflow 里现场 `gradle wrapper --gradle-version 8.13` 之类的生成命令——那会造成 AGP 9.x 配 Gradle 8.x 的版本错配。
- 「密钥有没有」的判断放在 shell step 内部：`if [ -n "$SIGNING_KEY" ]`。GitHub 的 `secrets.*` 不能出现在 step 级 `if:` 表达式里，否则整个 workflow 会被解析成 0 个 job。

### 4. 触发构建

- 打 tag 推送到 GitHub：`git tag v1.0.0 && git push origin v1.0.0` → 自动构建并创建 GitHub Release 附 APK；
- 或在 Actions 页面手动 `Run workflow`。

产物在 Actions 的 Artifacts（`app-release-apk`）中下载，文件名取决于是否配了密钥：`app-release.apk` 或 `app-release-unsigned.apk`；打 `v*` tag 时 workflow 会额外创建 GitHub Release 并附上 APK。

## 液态玻璃 + miuix-nav 导航

### 液态玻璃底栏（悬浮套壳）

`shared/src/commonMain/kotlin/component/liquid/` 与 `component/animation/`、`ui/` 来自 MIUIX 官方示例，**改编自 Kyant0/AndroidLiquidGlass（Apache-2.0）**。它把 `miuix-blur` 的 `LayerBackdrop` / `textureBlur` / `Highlight` / 设备倾斜传感器（`rememberDeviceTilt`）组合成 `IosLiquidGlassNavigationBar`。已在 `App.kt` 接线：

- `rememberLayerBackdrop()` 捕获“栏背后”内容；
- 内容区用 `.layerBackdrop(backdrop)` 标记；
- 底栏 `IosLiquidGlassNavigationBar(backdrop, isBlurActive)` 实时折射背后画面，外层再套 `textureBlur` 增强玻璃质感。

> 依赖：`miuix-blur`（已在 `shared/build.gradle.kts` 打开）。效果依赖 **Android `RuntimeShader`**（Android 12+ / 有 `RenderEffect` 的平台）；不支持时 `backdrop` 为 null，自动降级为纯色底栏。

### miuix-nav 页面栈导航

用 `miuix-nav` 替代了标准 Compose 的 `AnimatedContent`，提供：

- **页面栈**：顶层三 tab + 详情页（`Route.Detail(id)`），支持 push/pop/replace；
- **返回手势**：边缘滑动返回 + 系统预测性返回手势（`PredictiveBackHandler`）；
- **状态保存**：返回栈跨配置变更/进程重建自动保存（`@Serializable` + `rememberSaveable`）；
- **转场动画**：默认 MIUI 风格（`NavTransitions.MiuixDefault`），支持每页独立覆盖。

#### 路由定义

`Route.kt` 定义 `@Serializable sealed interface Route : NavKey`，内含三个 `data object`（`Home` / `Image` / `Settings`）和一个带参 `data class Detail(id: Int)`。`@Serializable` 是 `rememberNavBackStack` 序列化的硬要求，闭式多态无需 `SerializersModule`。

#### 用法示意

```kotlin
val nav = rememberNavController<Route>(Route.Home)

Scaffold(bottomBar = { ... }) { innerPadding ->
    NavDisplay(
        navController = nav,
        modifier = Modifier.fillMaxSize().padding(innerPadding),
    ) {
        entry<Route.Home> { HomePage(backdrop, snackbarHost, onOpenDetail = { nav.push(Route.Detail(it)) }) }
        entry<Route.Image> { ImagePage(backdrop, onOpenDetail = { nav.push(Route.Detail(it)) }) }
        entry<Route.Settings> { SettingsPage(themeMode) { themeMode = it } }
        entry<Route.Detail> { DetailPage(it.id, onBack = { nav.pop() }, backdrop = backdrop) }
    }
}
```

- 详情页 push 时 bottomBar 和 FAB 自动隐藏，全屏展示；
- 点击底部 tab 用 `nav.replace()` 切换（清空详情栈）；
- 系统返回键 / 边缘滑动返回调用 `nav.pop()`。

## UI 特性（均可在 `App.kt` 增删）

| 特性 | 实现 | 位置 |
|---|---|---|
| 大标题折叠 TopAppBar | 顶层 `MiuixScrollBehavior()` 传给各页 miuix 组件的 `topAppBarScrollBehavior`，栈顶决定标题/大标题；miuix `Scaffold` 内部已接管滚动，**不要**手写 `.nestedScroll(...)` | `App()` |
| 主题持久化 | `AppPrefs` 接口 + Android `SharedPreferences` 实现，主题/主题色/通知**重启保留** | `AppPrefs.kt` / `AndroidAppPrefs.kt` / `App()` |
| 下拉刷新 | `PullToRefresh` + `rememberPullToRefreshState`，模拟 800ms 后复位（首页 + 图片页） | `HomePage()` / `ImagePage()` |
| 左滑删除 + 撤销 | 自写 `SwipeToDeleteItem`（foundation `draggable`），左滑露出红色删除区，删除后 `Snackbar` 可撤销 | `HomePage()` / `SwipeToDeleteItem()` |
| 底部弹层 | `OverlayBottomSheet`（MIUIX 毛玻璃弹层） | `HomePage()` |
| 设置页标准化 | `miuix-preference` 的 `RadioButtonPreference`（主题/主题色单选）+ `SwitchPreference`（通知） | `SettingsPage()` |
| 图集状态机 | `LazyVerticalGrid` + Coil `SubcomposeAsyncImage`，带**加载中/失败**占位，点击进入详情页回显该图 | `ImagePage()` / `DetailPage()` |
| squircle 圆角 | `miuix-squircle` 的 `squircleSurface`，液态按钮在降级设备（无 RuntimeShader）上用连续圆角而非纯圆 | `LiquidButton()` |
| edge-to-edge | `MainActivity.enableEdgeToEdge()`，内容延伸到状态栏/导航栏之下 | `MainActivity.kt` |

> 图片页需要网络权限和 Coil 依赖，模板已配好：`AndroidManifest.xml` 加了 `INTERNET` 权限；`shared/build.gradle.kts` 的 commonMain 加了 `coil-compose`，androidMain 加了 `coil-network-okhttp`（Coil 3 的 OkHttp 网络变体只在 Android/JVM 平台有）。

## 常见问题

- **改应用名 / 包名**：改 `app/src/main/res/values/strings.xml` 的 `app_name`，以及各 `build.gradle.kts` 的 `namespace` / `applicationId` / 包目录。
- **构建报 `minCompileSdk=37`**：`miuix 0.9.4-rc01` 的 AAR 要求 compileSdk 37，`app/build.gradle.kts` 与 `shared/build.gradle.kts` 的 `compileSdk` 都要是 37（`targetSdk` 同为 37）。
- **AGP 9 的插件冲突**：`app/build.gradle.kts` 只应用 `com.android.application` + `org.jetbrains.kotlin.plugin.compose`，**不能**再应用 `org.jetbrains.kotlin.android`（AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报错）；`shared` 用 `com.android.kotlin.multiplatform.library` + `org.jetbrains.kotlin.multiplatform` + `org.jetbrains.compose` + compose / serialization 编译器插件，也不与 `com.android.library` 混用。
- **`shared` 用 KMP 新 DSL**：Android 目标配置内联在 `kotlin { android { namespace / compileSdk = 37 / minSdk = 24 / androidResources { enable = true } } }` 里，**没有**顶层 `android { }` 块，也**不再调用** `androidTarget()`；新插件默认关掉 Android 资源处理，用到资源必须显式 `androidResources { enable = true }`。
- **`gradle.properties` 只有 5 行**：`org.gradle.jvmargs`、`org.gradle.caching`、`android.useAndroidX`、`kotlin.code.style`、`android.nonTransitiveRClass`。迁移到新 DSL 后 `android.newDsl=false` 已删除，**别再加回去**。
- **开 R8 混淆**：模板默认 `isMinifyEnabled = false` 以保证首编通过。需要体积优化时，在 `app/build.gradle.kts` 将其设为 `true` 并补充 proguard 规则（Compose / MIUIX 的 keep 规则）。
- **换 MIUIX 模块**：在 `shared/build.gradle.kts` 的 `commonMain.dependencies` 增删。模板默认六个模块全开（`miuix-ui` / `miuix-icons` / `miuix-blur` / `miuix-nav` / `miuix-preference` / `miuix-squircle`），用不到可直接注释掉。
- **图片不显示**：确认真机/模拟器联网；`INTERNET` 权限和 `coil-network-okhttp` 依赖在模板里已配好，若自定义模块记得补上。
- **跑模拟器验证**：`adb install app/build/outputs/apk/release/*.apk`。注意 `app-release-unsigned.apk` 装不上，要先 `zipalign` + `apksigner` 签名。
- **上架 Play Store**：改用 `gradle :app:bundleRelease` 产出 AAB 再提交（Play 要求上传已签名的 AAB）。

### 写代码时的真实坑（都编译验证过）

- **作用域成员不要顶层 import**：`androidx.compose.foundation.layout.weight`、`androidx.compose.foundation.layout.matchParentSize` 这类是作用域内成员，import 了反而编译失败，删掉 import、靠接收者作用域解析。
- **Coil 3 组件在 `coil3.compose.*`**：如 `import coil3.compose.SubcomposeAsyncImage`，不是 `androidx.compose.*`。
- **`Icon` 用 miuix 的**：`import top.yukonga.miuix.kmp.basic.Icon`，不是 `androidx.compose.foundation.Icon`。
- **不要手写 nestedScroll**：miuix 的 `ScrollBehavior` 没有暴露 `nestedScroll.connection`，`.nestedScroll(scrollBehavior.nestedScroll.connection)` 会编译失败——miuix `Scaffold` 内部已接管滚动，把 `scrollBehavior` 传给 `topAppBarScrollBehavior` 即可。
