# MIUIX APK 模板（Compose Multiplatform）

用 **MIUIX 组件库**（`top.yukonga.miuix.kmp:miuix-ui`）搭建原生 Android 界面并产出 Release APK 的通用脚手架：**配好签名 Secrets 才产出已签名 APK**，未配置时产出 `app-release-unsigned.apk`（需自行用 `apksigner` 对齐并签名后才能安装/发布）。

全流程托管在 GitHub：把仓库推上去 → 配置签名 Secrets（不配的话 CI 的签名校验一步会直接判失败，见下文）→ 打 `v*` tag（或手动触发）→ GitHub Actions 自动编译并签名 → 产物为 APK（可下载 / 打 tag 时自动建 Release）。

> 本机**无需**安装 JDK / Android SDK；构建与签名全部在 GitHub Actions（自带 JDK 21 + Android SDK，并由 `setup-gradle` 提供 Gradle）完成。

**当前状态**：签名发布链路**已跑通**——本仓库已配置正式签名 Secrets，`v1.0.2` 已作为**已签名** Release 发布（APK Signature Scheme v2，可直接下载安装），见[已发布版本与产物校验](#已发布版本与产物校验)。
测试体系**仍在补齐**：仓库目前没有任何自动化测试，CI 只做编译 + `apksigner` 签名校验，尚无运行时验证，见[测试与验证现状](#测试与验证现状)。

## 能力清单（代码里实际有的）

- **悬浮液态玻璃底栏**：`miuix-blur` 的 `LayerBackdrop` / `textureBlur` / `Highlight` + 设备倾斜传感器（`rememberDeviceTilt`）组合成 `IosLiquidGlassNavigationBar`，实时折射背后画面；不支持 `RuntimeShader` 的设备自动降级为纯色底栏。
- **miuix-nav 页面栈**：三个顶层 tab（首页 / 图片 / 设置）+ 带参详情页 `Route.Detail(id)`，支持 push/pop/replace、边缘滑动返回、系统预测性返回手势、返回栈跨配置变更保存。
- **主题**：深/浅色与强调色切换（`ThemeController`），偏好经 `SharedPreferences` 持久化，重启保留。
- **首页**：大标题折叠 TopAppBar、下拉刷新、左滑删除 + Snackbar 撤销、`OverlayBottomSheet` 底部弹层、FAB。
- **图片页**：`LazyVerticalGrid` + Coil 3 `SubcomposeAsyncImage`，带加载中/失败占位，点击进详情页回显该图。
- **设置页**：`miuix-preference` 的 `RadioButtonPreference`（主题/主题色）+ `SwitchPreference`（通知）。
- **edge-to-edge**、squircle 连续圆角降级、自定义启动图标。
- **静态原型**：`preview.html`（浏览器打开的 HTML 版式稿，不参与 Gradle 构建）。
- **CI 与发布**：Actions 编译 release APK → `apksigner verify` 校验签名 → 上传 artifact → `v*` tag 自动建 GitHub Release 附 APK。

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
├── settings.gradle.kts             # 无根 build.gradle.kts，插件/依赖版本写在各模块 build 脚本里
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties   # 只提交 properties；gradlew 与 wrapper jar 未入库
├── preview.html                    # 浏览器里的 HTML 版式稿，不参与构建
├── shared/                         # KMP 库：commonMain 放 Compose UI
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/
│       ├── top/yukonga/miuixapptemplate/
│       │   ├── App.kt              # 页面 + 导航 + 主题
│       │   ├── AppPrefs.kt         # 偏好持久化接口（common）
│       │   └── Route.kt            # @Serializable 路由定义
│       ├── component/liquid/       # 液态玻璃底栏（改编自 Kyant0/AndroidLiquidGlass）
│       ├── component/animation/    # 按压形变 / 高光动效
│       └── ui/Theme.kt             # 主题色
├── app/                            # 纯 Android 应用模块
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/top/yukonga/miuixapptemplate/
│       │   ├── MainActivity.kt
│       │   └── AndroidAppPrefs.kt  # AppPrefs 的 SharedPreferences 实现
│       └── res/...                 # 图标、主题、字符串
├── skills/generate-miuix-app/      # 自动生成同类 App 的 skill
└── .github/workflows/build-apk.yml # 自动构建 + 签名 + 签名校验 + 建 Release
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

**推荐：openssl 直接生成 PKCS12，不需要装 JDK**（本仓库 release 密钥就是这么产出来的）：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 10950 -nodes \
  -keyout key.pem -out cert.pem \
  -subj "/C=CN/O=myorg/CN=my-release"

openssl pkcs12 -export -inkey key.pem -in cert.pem -out release.p12 \
  -name mykey -passout pass:'<你的口令>'

# 转成单行 base64，作为 SIGNING_KEY 的值
base64 -w0 release.p12
```

用 PKCS12 时 `app/build.gradle.kts` 必须显式声明 `storeType = "PKCS12"`，
否则 AGP 按默认 JKS 读取会失败（模板已设好）。

**备选：本机有 JDK 时用 keytool**（产出 JKS，此时把 `storeType` 去掉或改成 `"JKS"`）：

```bash
keytool -genkeypair -v \
  -keystore release.keystore -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mykey
base64 -w0 release.keystore
```

> ⚠️ keystore 与口令**必须自行异地备份**，且绝不能提交进仓库（`.gitignore` 已忽略 `*.jks` / `*.p12` / `*.keystore`）。
> 丢了它，这个 `applicationId` 就再也无法以覆盖升级的方式装到已装用户机上。

### 2. 在仓库配置 Secrets

`Settings → Secrets and variables → Actions → New repository secret`：

| Secret | 内容 |
|---|---|
| `SIGNING_KEY` | 上面 `base64 -w0 release.p12` 的输出（单行 base64 的 PKCS12 内容） |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | `mykey`（上面的 alias） |
| `KEY_PASSWORD` | 密钥密码 |

> 四个名字都要对上：workflow 把 `SIGNING_KEY` 解成 `keystore.p12`，再以 `KEYSTORE_PASS` / `KEY_ALIAS` / `KEY_PASSWORD` 三个环境变量传给 Gradle（`app/build.gradle.kts` 里的 `signingProp()` 先读环境变量、再读 `local.properties`）。
>
> 缺任何一个密钥时 AGP 干脆不配 signingConfig，产物是 **`app-release-unsigned.apk`**——**不会**回退成 debug 签名的可安装包。而且本仓库 workflow 的 **Verify APK signature** 一步会把未签名产物直接判为 CI 失败，所以 fork 之后要么配齐四个 Secrets，要么放宽那一步，否则分支上的构建永远是红的。这种 unsigned APK 若真要安装/上架，需自行 `zipalign` + `apksigner sign`。

### 3. 构建命令与签名判定（真实形态）

- CI 用 `gradle/actions/setup-gradle@v6` 提供与 AGP 9.x 匹配的 Gradle 9.x（已在 PATH 上），构建命令是 `gradle :app:assembleRelease --no-daemon`，**不是** `./gradlew ...`（仓库未提交 wrapper）。
- 不要在 workflow 里现场 `gradle wrapper --gradle-version 8.13` 之类的生成命令——那会造成 AGP 9.x 配 Gradle 8.x 的版本错配。
- 「密钥有没有」的判断放在 shell step 内部：`if [ -n "$SIGNING_KEY" ]`。GitHub 的 `secrets.*` 不能出现在 step 级 `if:` 表达式里，否则整个 workflow 会被解析成 0 个 job。
- 构建后有一步 **Verify APK signature**：产物文件名含 `unsigned` 就直接让 CI 失败，并用 runner 自带的 `apksigner verify --print-certs` 打印签名证书指纹——避免把装不上的包挂到 Release 页上。
- workflow 顶层**必须**写 `permissions: contents: write`：`softprops/action-gh-release` 用 `GITHUB_TOKEN` 建 Release，而缺省权限只有 read。本仓库第一次打 tag 时就是漏了这行，Release 步骤报 403 `Resource not accessible by integration`（构建本身是绿的，很容易看漏），现已修好。
- Secrets 也可以不走网页、直接用 API 批量写入（自动化场景）：先 `GET /repos/{owner}/{repo}/actions/secrets/public-key` 拿 `key_id` 与公钥，用 NaCl sealed box（PyNaCl `public.SealedBox`）加密，再 `PUT /repos/{owner}/{repo}/actions/secrets/{NAME}`。

### 4. 触发构建

- 打 tag 推送到 GitHub：`git tag v1.0.3 && git push origin v1.0.3` → 自动构建并创建 GitHub Release 附 APK。tag 版本要与 `app/build.gradle.kts` 的 `versionName` / `versionCode` 对上——`versionCode` 不递增的话，老用户收到也升不上去；
- 或在 Actions 页面手动 `Run workflow`（手动触发不建 Release，只出 artifact）。

产物在 Actions 的 Artifacts（`app-release-apk`）中下载，文件名取决于是否配了密钥：`app-release.apk` 或 `app-release-unsigned.apk`；打 `v*` tag 时 workflow 会额外创建 GitHub Release 并附上 APK。

## 已发布版本与产物校验

| tag | versionName / versionCode | Release 资产 | 状态 |
|---|---|---|---|
| [`v1.0.2`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.2) | `1.0.2` / `2` | `app-release.apk`（9306061 字节 ≈ 8.87 MB） | **已签名，可直接下载安装** |
| `v1.0.1` | — | 无 APK 资产（只有 source zip/tar.gz） | 签名链路启用前的构建 |

下载：`https://github.com/guocheng1378/miuix-apk-template/releases/download/v1.0.2/app-release.apk`

`v1.0.2` 的签名与完整性（CI `apksigner verify --print-certs` 与 Release 页两处一致）：

- 签名方案：**APK Signature Scheme v2**，RSA 2048，单签名者（自签证书）
- **APK SHA-256**：`ba6ae10d3d8e1136910e7957a76777aa1325749f8530a72538b766bae45d77e5`
- **证书 SHA-256**：`445a46ddcad6465947735503f6d80f2b556337ff5bd6a67470f378e1092195c7`

拿到 APK 后自行核对：

```bash
# 1) 完整性：结果应等于上面的 APK SHA-256
sha256sum app-release.apk

# 2) 签名与证书指纹：Signer #1 certificate SHA-256 digest 应等于上面的证书 SHA-256
#    apksigner 在 Android SDK 的 build-tools/<版本>/ 下，本机需有 JDK + Android SDK
apksigner verify --verbose --print-certs app-release.apk
```

> GitHub 会在每个 Release 资产上直接标 `sha256:<摘要>`，可与上面第一条对照。
> 换自己的密钥后这两个指纹都会变，别拿本仓库的值去校验 fork 的产物。

## 测试与验证现状

**仓库目前没有任何自动化测试**：没有 `test/` / `androidTest/` 源码集，没有单元测试、没有 Compose UI 测试、没有截图基线。CI（`.github/workflows/build-apk.yml`）只有两步实质性验证——

1. `gradle :app:assembleRelease --no-daemon`：只能证明**编译通过**；
2. **Verify APK signature**（文件名含 `unsigned` 即失败 + `apksigner verify`）：只能证明**签名正确**，完全不碰运行时。

也就是说，**没有任何一步真正安装并驱动过这个 App**。

正在补齐（本轮改动，尚未全部落地，别当成已完成）：

- **预览截图回归**：把界面渲染成图与基线比对，防止 UI 改版悄悄跑偏；
- **模拟器冒烟**：在 CI 里起模拟器安装并启动 Activity，检查不崩溃。

**仍未执行**：真机运行时冒烟（`adb install` 后逐页操作）。开发环境没有 JDK / Android SDK / adb / 设备，所以「装得上、点得动、真机上液态玻璃是什么观感」目前**没有任何验证记录**，只有静态编译与签名层面的证据。

## 限制与未验证项

- **本机没 JDK / Android SDK 就构建不了**：仓库只提交了 `gradle-wrapper.properties`，没有 `gradlew` 和 wrapper jar，本地既跑不了 `./gradlew`，也没有 `gradle` 可配 AGP 9.x。所有「构建通过」的结论都来自 GitHub Actions，不是本地实测。
- **模拟器 / 软件渲染 ≠ 真机质感**：液态玻璃依赖 Android `RuntimeShader` / `RenderEffect`（Android 12+ 且平台实现完整）。模拟器与软件渲染下模糊、折射、高光边缘的表现和真机差得很远，**看模拟器截图判断玻璃效果不可靠**；不支持的平台 `backdrop` 为 null，直接降级成纯色底栏。
- **真机冒烟未做**：逐页操作、手势返回、下拉刷新手感、左滑删除阈值都没有人工或自动化验证记录（见上一节）。
- **自签证书，系统会提示「来源不受信任」**：预期行为——没上架商店、没走 Play App Signing。首次安装需在系统里允许「安装未知应用」；换密钥重新签名会导致老包无法覆盖升级。
- **keystore 一旦丢失就无法覆盖升级**：同一 `applicationId` 必须用同一把签名密钥。`release.p12` 与口令必须异地备份，且永远不能提交进仓库（`.gitignore` 已忽略 `*.jks` / `*.p12` / `*.keystore`）；丢了只能换包名重发，或让老用户卸载重装。
- **产物未开 R8**：`isMinifyEnabled = false`，所以 `v1.0.2` 的 APK 约 8.9 MB。开混淆要自行补 Compose / MIUIX 的 keep 规则。

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
- **返回手势**：`NavDisplay` 自带边缘滑动返回与系统预测性返回手势（`App.kt` 里没有手写 handler）；
- **状态保存**：返回栈跨配置变更/进程重建自动保存（`@Serializable` 路由）；
- **转场动画**：miuix-nav 默认转场，详情页 push/pop 自带过渡。

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
- **跑模拟器 / 真机验证**：`adb install app/build/outputs/apk/release/app-release.apk`（Release 页上的 `app-release.apk` 也可直接下载装机）。注意 `app-release-unsigned.apk` 装不上，要先 `zipalign` + `apksigner` 签名。**本仓库的开发环境没有 adb 和设备，这条路径至今没实际跑过**，装机后是否崩溃属于未验证项。
- **上架 Play Store**：改用 `gradle :app:bundleRelease` 产出 AAB 再提交（Play 要求上传已签名的 AAB）。

### 写代码时的真实坑（都编译验证过）

- **作用域成员不要顶层 import**：`androidx.compose.foundation.layout.weight`、`androidx.compose.foundation.layout.matchParentSize` 这类是作用域内成员，import 了反而编译失败，删掉 import、靠接收者作用域解析。
- **Coil 3 组件在 `coil3.compose.*`**：如 `import coil3.compose.SubcomposeAsyncImage`，不是 `androidx.compose.*`。
- **`Icon` 用 miuix 的**：`import top.yukonga.miuix.kmp.basic.Icon`，不是 `androidx.compose.foundation.Icon`。
- **不要手写 nestedScroll**：miuix 的 `ScrollBehavior` 没有暴露 `nestedScroll.connection`，`.nestedScroll(scrollBehavior.nestedScroll.connection)` 会编译失败——miuix `Scaffold` 内部已接管滚动，把 `scrollBehavior` 传给 `topAppBarScrollBehavior` 即可。
