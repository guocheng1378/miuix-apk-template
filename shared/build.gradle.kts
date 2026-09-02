@file:OptIn(ExperimentalRoborazziApi::class)

import com.github.takahirom.roborazzi.ExperimentalRoborazziApi

plugins {
    // AGP 9 内置 Kotlin 后，KMP 库模块必须用专用 Android 插件，
    // 不能再和 com.android.library 混用（否则 kotlin 扩展名冲突）。
    id("com.android.kotlin.multiplatform.library") version "9.3.2"
    id("org.jetbrains.kotlin.multiplatform") version "2.4.10"
    id("org.jetbrains.compose") version "1.12.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    // miuix-nav 的路由是 @Serializable，需要序列化插件生成序列化器
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.10"
    // 截图回归：1.73.0 起内置 AndroidRoborazziConfigurator.configureKmpAndroidLibrary()，
    // 专门适配上面这个新 KMP 库插件（旧版本只认 com.android.library/application）。
    id("io.github.takahirom.roborazzi") version "1.73.0"
}

kotlin {
    // 新 DSL：Android 目标配置内联在 kotlin { android { ... } } 里，
    // 不再有顶层 android { } 块，也不再调用 androidTarget()。
    android {
        namespace = "top.yukonga.miuixapptemplate.shared"
        // miuix 0.9.4-rc01 的 AAR 元数据要求 minCompileSdk=37
        compileSdk = 37
        minSdk = 24
        // 新插件默认关闭 Android 资源处理，用到 res/composeResources 必须显式打开
        androidResources { enable = true }
        // 新 KMP 插件把原来的 androidUnitTest 源集改名为 androidHostTest（src/androidHostTest），
        // 且默认不启用。withHostTest 是官方提供的配置钩子；isIncludeAndroidResources 必须打开，
        // 否则 Robolectric 拿不到合并后的资源，Compose 渲染时会因缺资源而崩。
        // （roborazzi 插件检测不到这一行时只 logger.warn，不会报错，所以这步容易被忽略。）
        withHostTest {
            isIncludeAndroidResources = true
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.ui)

            // MIUIX 组件库（核心 + 图标）
            implementation("top.yukonga.miuix.kmp:miuix-ui:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-icons:0.9.4-rc01")
            // 液态玻璃底栏所需（注意：miuix-blur 在 Android 上要求 minSdk 33）
            implementation("top.yukonga.miuix.kmp:miuix-blur:0.9.4-rc01")
            // 页面栈导航：返回手势 / 状态保存 / 详情页 push
            implementation("top.yukonga.miuix.kmp:miuix-nav:0.9.4-rc01")
            // 设置页标准化组件（RadioButtonPreference / SwitchPreference 等）
            implementation("top.yukonga.miuix.kmp:miuix-preference:0.9.4-rc01")
            // iOS 风连续圆角（squircle）形状
            implementation("top.yukonga.miuix.kmp:miuix-squircle:0.9.4-rc01")
            // @Serializable 路由所需的序列化运行时
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-core:1.11.0")
            // 图片页：Coil 3 多平台加载网络图
            implementation("io.coil-kt.coil3:coil-compose:3.6.1")
            // preview/Previews.kt 里的 @Preview 注解。
            // 不用 compose.components.preview：该访问器在 Compose Multiplatform 1.12 起
            // 全量标了 @Deprecated("Specify dependency directly")，一律写显式坐标。
            // CMP 1.12 的 commonMain @Preview 在 Android classpath 上就是
            // androidx.compose.ui.tooling.preview.Preview（ui-tooling-preview-android 转发到
            // androidx 工件），所以 ComposablePreviewScanner 能直接扫到，无需自定义 tester。
            implementation("org.jetbrains.compose.ui:ui-tooling-preview:1.12.0")
        }

        androidMain.dependencies {
            // Coil 3 在 Android 上通过 OkHttp 加载网络图
            implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.1")
        }

        // 新 KMP 插件下，JVM 侧 Android 单测源集叫 androidHostTest（不是 src/test）。
        // roborazzi 的 generateComposePreviewRobolectricTests 会自动往这个源集生成测试类
        // （走 unitTestSources.kotlin.addGeneratedSourceDirectory），所以这里不需要手写任何测试代码，
        // 只需把官方 sample-generate-preview-tests 的那 5 件依赖声明齐。
        getByName("androidHostTest") {
            dependencies {
                implementation("junit:junit:4.13.2")
                // Robolectric 4.14.1 提供 ShadowNativeRuntimeShader / ShadowNativeRenderEffect，
                // 让 @GraphicsMode(NATIVE) 能真正走 RuntimeShader 路径；但内嵌的 Skia 仍不认
                // AGSL 的 `layout(color)` 限定符，miuix 的 squircle/blur 着色器在它下面会构造即抛
                // IllegalArgumentException——所以带 AGSL 的预览由 emulator 冒烟 job 覆盖，本 test 源集只
                // 扫 preview.settings（见上方 roborazzi { packages } 注释）。
                implementation("org.robolectric:robolectric:4.14.1")
                // 扫描 @Preview 的引擎。用 :android 而非 :common —— CPS 的 :common 硬编码旧包名
                // com.android.tools.idea.compose.preview 且 0.10.0 已移除，用了会一个预览都扫不到。
                implementation("io.github.sergio-sastre.ComposablePreviewScanner:android:0.9.3")
                // 把 CPS 扫到的 preview 接到 roborazzi 截图管线上。
                // 注意它的 android variant 只 api 传递 roborazzi / roborazzi-compose /
                // roborazzi-annotations，ui-test 和 androidx.test 链都不带，必须下面单独声明。
                implementation("io.github.takahirom.roborazzi:roborazzi-compose-preview-scanner-support:1.73.0")
                // 生成的测试用 createComposeRule()；androidx.test:core / monitor / espresso 由它传递带入
                // （这也是官方样例唯一声明的 test 侧 UI 依赖，无需再手写 androidx.test:*）。
                implementation("org.jetbrains.compose.ui:ui-test-junit4:1.12.0")
            }
        }
    }
}

// 截图回归配置。generateComposePreviewRobolectricTests 是实验 API，
// 故文件顶部用 @file:OptIn(ExperimentalRoborazziApi::class)（与官方样例写法一致）。
roborazzi {
    generateComposePreviewRobolectricTests {
        enable = true
        // 只扫 preview.settings 包：里面只有 SettingsPageLight/Dark，它们只用到 miuix-preference
        // 与主题，不含任何 AGSL 着色器，在 Robolectric（JVM/layoutlib）下能正常光栅化。
        //
        // 玻璃/液态预览（液态底栏、HomePage 的 Card squircle、整棵 App 的真玻璃路径）刻意不扫：
        // miuix 的 AGSL 着色器用了 `layout(color)` 限定符，而 Robolectric 4.14.1 自带的
        // ShadowNativeRuntimeShader / 其内嵌 Skia 并不支持该限定符，构造 RuntimeShader 时直接抛
        // IllegalArgumentException（"error: 'color' is not a valid layout qualifier"），8 条预览里有
        // 6 条因此必红。这是 Robolectric 的渲染限制，不是 app bug——同一套代码在真机/模拟器上
        // 由 build-apk.yml 的 emulator 冒烟 job 验证能正常启动与渲染。
        // 把玻璃预览留在 preview/Previews.kt（包名 preview，不被本扫描命中），作为 emulator 冒烟
        // 的 golden 参考来源，未来可接成 emulator 上的像素比对。
        packages = listOf("preview.settings")
        // 刻意不覆盖 robolectricConfig：默认值已是 sdk=["[33]"] + Pixel_4a。
        // miuix-blur 的 AAR 要求 minSdk 33，同时 isRuntimeShaderSupported() 判的也是 >= 33，
        // 把 sdk 改成别的值要么让模糊代码整段不执行，要么直接不满足库要求。
    }
}

tasks.withType<Test>().configureEach {
    // 下面三项等价于官方样例里 legacy android.testOptions.unitTests.all { } 的内容。
    // 新 KMP 插件没有那个钩子，而本模块的根 gradle.properties 不在本次改动范围内，
    // 所以只能在模块构建脚本里给 Test 任务补 systemProperty。
    // pixelCopyRenderMode=hardware：配合 @GraphicsMode(NATIVE)，让截图取自真实
    // OpenGL/layoutlib 光栅化结果，否则软件渲染下字体与圆角会整体偏移。
    systemProperty("robolectric.pixelCopyRenderMode", "hardware")
    // 让 roborazzi 按 context 目录解析输出路径，避免 Gradle 9 下多任务共享输出目录时
    // 出现绝对路径冲突（roborazzi issue #830）。
    systemProperty("roborazzi.record.filePathStrategy", "relativePathFromRoborazziContextOutputDirectory")
    // 整屏截图 + AGSL 着色器比较吃堆，默认堆容易 OOM。
    maxHeapSize = "2048m"
    // Gradle 默认的 test 日志只打「异常类名 + 调用位置」，不带消息体和堆栈。
    // CI 上排查预览渲染失败时，只有类名的话等于没有信息（实际踩过：6 条预览全报
    // IllegalArgumentException，日志里连一句 message 都没有）。
    testLogging {
        events = setOf(org.gradle.api.tasks.testing.logging.TestLogEvent.FAILED)
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        showExceptions = true
        showCauses = true
        showStackTraces = true
    }
}
