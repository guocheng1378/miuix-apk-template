# 工程结构与构建配置

模板仓库 `guocheng1378/miuix-apk-template`（分支 `master`）的实际形态。
以下每一项都是逐个文件读出来的，不是推测。

## 目录结构

```
miuix-apk-template/
├── settings.gradle.kts
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties
├── LICENSE                        # Apache-2.0
├── .gitignore
├── shared/
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/
│       ├── top/yukonga/miuixapptemplate/
│       │   ├── App.kt             # MiuixTheme + Scaffold + 导航 + 底栏接线 + 各页面
│       │   ├── Route.kt           # @Serializable 路由
│       │   └── AppPrefs.kt        # 跨平台偏好接口
│       ├── ui/Theme.kt            # KeyColors / keyColorFor / isInDarkTheme
│       ├── component/liquid/      # LiquidGlassNavigationBar（改编 Kyant0/AndroidLiquidGlass, Apache-2.0）
│       │   ├── LiquidGlassNavigationBar.kt
│       │   ├── CombinedBackdrop.kt
│       │   ├── Lens.kt
│       │   ├── Vibrancy.kt
│       │   └── InnerShadow.kt
│       ├── component/animation/
│       │   ├── InteractiveHighlight.kt
│       │   └── DampedDragAnimation.kt
│       ├── preview/Previews.kt            # 含 AGSL 玻璃路径的预览，emulator 冒烟的 golden 参考
│       └── preview/settings/SettingsPreviews.kt   # 只依赖 miuix-preference，JVM 侧可渲染
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/<pkg>/MainActivity.kt        # enableEdgeToEdge + 注入 AppPrefs
│       ├── kotlin/<pkg>/AndroidAppPrefs.kt     # SharedPreferences 实现
│       └── res/values|drawable|mipmap-anydpi-v26/...
└── .github/workflows/build-apk.yml
```

> **只有 `App.kt` / `Route.kt` / `AppPrefs.kt` 在 `<pkg>` 包下**。`component.liquid`、
> `component.animation`、`ui`、`preview`、`preview.settings` 的 package 就是字面这几段，
> 前面**没有** `<pkg>` 前缀（实测各文件首行 `package` 声明）。改包名时别顺手把它们也
> 挪进去——`shared/build.gradle.kts` 里 roborazzi 的 `packages = listOf("preview.settings")`
> 是按这个字面包名匹配的，挪了就一条预览都扫不到。

> **仓库没有根 `build.gradle.kts`**。所有构建逻辑在 `settings.gradle.kts` + 两个模块的
> `build.gradle.kts` 里。别去新建一个根构建文件。

> 仓库**没有提交** `gradlew` 与 `gradle/wrapper/gradle-wrapper.jar`，只保留了
> `gradle-wrapper.properties`（记录 Gradle `9.7.1`）。CI 靠
> `gradle/actions/setup-gradle@v6` 提供 Gradle；本地构建需自备 Gradle 9.x + Android SDK，
> 或自行补交 wrapper jar。这也是 CI 里构建命令用 `gradle` 而不是 `./gradlew` 的原因。

> 根目录有 **Apache-2.0 的 `LICENSE` 文件**（11342 字节，提交 `b0e95b9` 补入）。
> 派生新 app 时若沿用本模板代码（含改编的 `LiquidGlassNavigationBar.kt`），
> 保留 Apache-2.0 许可与 NOTICE/来源注释。

## settings.gradle.kts

- `pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }`
- `dependencyResolutionManagement` 的 `repositoriesMode` 设为 **`PREFER_SETTINGS`**，
  仓库列表：`google()`、`mavenCentral()`、
  `https://maven.pkg.jetbrains.space/public/p/compose/dev`
- `rootProject.name = "miuix-apk-template"`
- `include(":app", ":shared")`

`PREFER_SETTINGS` 是必要的：Compose Multiplatform 插件要从 JetBrains 的 dev 仓库取，
若模块自己声明仓库会绕过它。

## shared/build.gradle.kts（KMP 库）

插件（版本写在 `plugins {}` 块里）：

```kotlin
@file:OptIn(ExperimentalRoborazziApi::class)
import com.github.takahirom.roborazzi.ExperimentalRoborazziApi

plugins {
    id("com.android.kotlin.multiplatform.library") version "9.3.2"  // AGP 9 的 KMP 库专用插件
    id("org.jetbrains.kotlin.multiplatform") version "2.4.10"
    id("org.jetbrains.compose") version "1.12.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.10"
    id("io.github.takahirom.roborazzi") version "1.73.0"            // 截图回归
}
```

`generateComposePreviewRobolectricTests` 是实验 API，所以文件头要有
`@file:OptIn(ExperimentalRoborazziApi::class)` 加对应 import，否则编译不过。

Android 目标用 **KMP 新 DSL**——内联在 `kotlin { android { ... } }` 里，
**没有**顶层 `android { }` 块，**也不调用** `androidTarget()`：

```kotlin
kotlin {
    android {
        namespace = "top.yukonga.miuixapptemplate.shared"
        compileSdk = 37          // miuix 0.9.4-rc01 AAR 要求 minCompileSdk=37
        minSdk = 24
        androidResources { enable = true }   // 新插件默认关闭资源处理，不开则 res 不生效
        withHostTest { isIncludeAndroidResources = true }   // 见下
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
            implementation("org.jetbrains.compose.ui:ui-tooling-preview:1.12.0")  // @Preview 注解
        }
        androidMain.dependencies {
            implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.1")  // 只能放 androidMain
        }
        getByName("androidHostTest") {
            dependencies { /* 见下 5 件 */ }
        }
    }
}
```

- **不能**用 `com.android.library`：AGP 9 内置 Kotlin 后与 KMP 扩展名冲突。
- `miuix-nav` 在 Maven Central 上**只有 `0.9.4-rc01` 这一个版本**（实测
  `maven-metadata.xml`），没有更早的可回退——降级方案不存在，别浪费时间找。
- `@Preview` 用显式坐标 `org.jetbrains.compose.ui:ui-tooling-preview:1.12.0`，
  **不要**写 `compose.components.preview` 访问器——CMP 1.12 起它全量 `@Deprecated`。

### 截图回归骨架（新工程要复刻）

新 KMP 插件把原 `androidUnitTest` 源集**改名**为 `androidHostTest`，且默认不启用。
roborazzi 的 `generateComposePreviewRobolectricTests` 自动往这个源集生成测试类，
所以**不需要手写任何测试代码**，只要把这几样配齐：

1. `android { withHostTest { isIncludeAndroidResources = true } }`——不开则 Robolectric
   拿不到合并资源，Compose 渲染时因缺资源崩。roborazzi 检测不到这行时**只 warn 不报错**，
   所以极易漏。
2. `getByName("androidHostTest")` 的 5 件依赖（官方 sample 的那 5 件）：
   `junit:junit:4.13.2`、`org.robolectric:robolectric:4.14.1`、
   `io.github.sergio-sastre.ComposablePreviewScanner:android:0.9.3`（必须 `:android` 变体，
   `:common` 硬编码旧包名且 0.10.0 已移除，用了会一个预览都扫不到）、
   `io.github.takahirom.roborazzi:roborazzi-compose-preview-scanner-support:1.73.0`、
   `org.jetbrains.compose.ui:ui-test-junit4:1.12.0`（`androidx.test:*` 链由它传递带入）。
3. `roborazzi { generateComposePreviewRobolectricTests { enable = true; packages =
   listOf("preview.settings") } }`。
4. `tasks.withType<Test>` 里补 `systemProperty("robolectric.pixelCopyRenderMode", "hardware")`、
   `systemProperty("roborazzi.record.filePathStrategy", "relativePathFromRoborazziContextOutputDirectory")`、
   `maxHeapSize = "2048m"` 和 `testLogging`（新 KMP 插件没有旧的 `android.testOptions.unitTests.all {}`
   钩子，只能在模块构建脚本里给 Test 任务补）。

**为什么 `packages` 只列 `preview.settings`**：本仓库 8 条 `@Preview` 里 6 条在 `preview/`
（液态底栏、HomePage、整棵 App——都带 AGSL 着色器），2 条在 `preview.settings`
（`SettingsPageLight/Dark`，只用 miuix-preference 与主题）。Robolectric 内嵌的 Skia 不认
AGSL 的 `layout(color)` 限定符，带 AGSL 的预览构造 `RuntimeShader` 时直接抛
`IllegalArgumentException`，全扫就是 6 条必红。这是 Robolectric 的渲染限制不是 app bug，
玻璃路径改由 `build-apk.yml` 的 emulator 冒烟覆盖。细节见 `pitfalls.md` G3。

## app/build.gradle.kts（应用模块）

```kotlin
plugins {
    id("com.android.application") version "9.3.2"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
}
```

- **不含** `org.jetbrains.kotlin.android`（AGP 9 已内置 Kotlin 支持，同时应用会在
  配置阶段报 `Remove the 'org.jetbrains.kotlin.android' plugin`；见 SKILL.md
  「不可协商项」，按内容找别按序号找——那份清单会插队重排）。
- 依赖：`implementation(project(":shared"))` +
  `implementation("androidx.activity:activity-compose:1.13.0")`（提供 `enableEdgeToEdge`）。
- `namespace` / `applicationId` = `top.yukonga.miuixapptemplate`；
  `compileSdk 37` / `minSdk 24` / `targetSdk 37`；`compileOptions` 用 Java 21。
- `isMinifyEnabled = false`（release 未开混淆——开之前要补 proguard 规则，miuix/Coil 都有反射点）。
- **版本号不手工递增**。取值优先级
  `VERSION_CODE`/`VERSION_NAME` 环境变量 > CI 派生值 > 本地兜底（`defaultVersionCode = 2` /
  `defaultVersionName = "1.0.2"`）。CI 派生值：`versionCode` 取 `GITHUB_RUN_NUMBER` 并与兜底值
  取 `max`（防换 workflow 后倒退，Google Play 拒收）；`versionName` 在
  `GITHUB_REF_TYPE == "tag"` 时取 tag 名去掉前导 `v`。所以发版只需打 tag。
  这段取值逻辑必须放在 `plugins {}` **之后**——Gradle Kotlin DSL 只允许
  `buildscript`/`plugins` 块作脚本头部。
- 签名配置用 `signingProp(name)` helper：**优先读环境变量，回退 `local.properties`**，
  只在 keystore 文件存在时才建 `signingConfig`，块内含 `storeType = "PKCS12"`。
  读的变量名是 `KEYSTORE_PATH` / **`KEYSTORE_PASS`** / `KEY_ALIAS` / `KEY_PASSWORD`
  ——注意 `KEYSTORE_PASS` 与 GitHub Secret 名 `KEYSTORE_PASSWORD` 不一致，
  靠 workflow 的 `env:` 映射（详见 `ci-workflow.md`）。模板见
  `assets/signing-config.gradle.kts.snippet`。

## gradle.properties（实测正好这 5 行）

```properties
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
org.gradle.caching=true
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
```

**不要**加 `android.newDsl=false`——shared 迁移到 KMP 新 DSL 后该行已删除，留着会误导。

## AndroidManifest.xml（app 模块）

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-sdk tools:overrideLibrary="top.yukonga.miuix.kmp.blur" />
```

加上 `android:exported="true"`（targetSdk 31+ 必须）、`configChanges`、
`MAIN`/`LAUNCHER` 的 `intent-filter`。

- `INTERNET` 是 Coil 加载网络图的前提。
- `tools:overrideLibrary` 用来压掉 blur 模块 `minSdk 33` 与工程 `minSdk 24` 的冲突，
  代价是低版本设备上必须走降级分支（见 `miuix-api.md`）。

图标：`mipmap-anydpi-v26/ic_launcher.xml`（adaptive-icon）→
`res/values/colors.xml` 的 `ic_launcher_background` + `res/drawable/ic_launcher_foreground.xml`。

## 主题持久化（跨重启保留）

- `commonMain` 定义接口
  `interface AppPrefs { var themeMode: Int; var keyColorIndex: Int; var notificationsEnabled: Boolean }`
- `app` 模块用 `class SharedPreferencesAppPrefs(context) : AppPrefs`（同步读写，无需挂起）
- `App(prefs: AppPrefs)` 初始化时读 prefs，运行中写回。
  `themeMode` 约定 `0=System 1=Light 2=Dark 3=MonetSystem`
  （App.kt 里映射到 `ColorSchemeMode`，`else` 分支落 `System`）。

## Android 侧接线

`MainActivity.onCreate`：

```kotlin
enableEdgeToEdge()
setContent { App(prefs = SharedPreferencesAppPrefs(this)) }
```
