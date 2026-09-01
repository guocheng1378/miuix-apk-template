# MIUIX APK 模板（Compose Multiplatform）

用 **MIUIX 组件库**（`top.yukonga.miuix.kmp:miuix-ui`）搭建原生 Android 界面，并产出**已签名的 Release APK** 的通用脚手架。

全流程托管在 GitHub：把仓库推上去 → 配置 Secrets → 打 `v*` tag（或手动触发）→ GitHub Actions 自动编译并签名 → 产物为 APK（可下载 / 自动建 Release）。

> 本机**无需**安装 JDK / Android SDK；构建与签名全部在 GitHub Actions（自带 JDK 21 + Android SDK）完成。

## 技术栈（已核实可用组合）

| 组件 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`miuix-ui` + `miuix-icons` + `miuix-blur` + `miuix-nav` + `miuix-preference` + `miuix-squircle`） |
| Coil | `3.6.1`（`coil-compose` common + `coil-network-okhttp` android） |
| JDK（CI） | `21`（Zulu） |
| Gradle | `8.13` |

## 工程结构

```
miuix-apk-template/
├── settings.gradle.kts
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties
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
└── .github/workflows/build-apk.yml # 自动构建 + 签名
```

UI 写在 `shared/src/commonMain/kotlin/top/yukonga/miuixapptemplate/App.kt`，
用 MIUIX 组件（`TopAppBar` / `Scaffold` / `Card` / `Switch` / `Slider` / `Button` / `Text`）+ `MiuixTheme` 主题。
把这段 Composable 换成你自己的界面即可。

## 本地构建（可选，需本机有 JDK 21 + Android SDK）

```bash
./gradlew :app:assembleRelease
# 产物：app/build/outputs/apk/release/app-release.apk（未配密钥时用 debug 签名）
```

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

> 不配置 Secrets 也能构建：release 会回退到 AGP 自带的 debug 签名，产出可安装的 APK（非发布签名）。

### 3. 触发构建

- 打 tag 推送到 GitHub：`git tag v1.0.0 && git push origin v1.0.0` → 自动构建并创建 GitHub Release 附 APK；
- 或在 Actions 页面手动 `Run workflow`。

产物在 Actions 的 Artifacts（`app-release-apk`）中下载；打 tag 时也会出现在 Releases 里。

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
| 大标题折叠 TopAppBar | 顶层 `Scaffold` 挂 `MiuixScrollBehavior`，各页内容挂 `nestedScroll(connection)`，栈顶决定标题/大标题 | `App()` |
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
- **开 R8 混淆**：模板默认 `isMinifyEnabled = false` 以保证首编通过。需要体积优化时，在 `app/build.gradle.kts` 将其设为 `true` 并补充 proguard 规则（Compose / MIUIX 的 keep 规则）。
- **换 MIUIX 模块**：在 `shared/build.gradle.kts` 的 `commonMain` 取消注释 `miuix-preference` / `miuix-squircle` 等。`miuix-blur`、`miuix-nav` 已默认打开。
- **图片不显示**：确认真机/模拟器联网；`INTERNET` 权限和 `coil-network-okhttp` 依赖在模板里已配好，若自定义模块记得补上。
- **跑模拟器验证**：`adb install app/build/outputs/apk/release/*.apk`。
- **上架 Play Store**：改用 `./gradlew :app:bundleRelease` 产出 AAB 再提交。
