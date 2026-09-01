plugins {
    // AGP 9 内置 Kotlin 后，KMP 库模块必须用专用 Android 插件，
    // 不能再和 com.android.library 混用（否则 kotlin 扩展名冲突）。
    id("com.android.kotlin.multiplatform.library") version "9.3.2"
    id("org.jetbrains.kotlin.multiplatform") version "2.4.10"
    id("org.jetbrains.compose") version "1.12.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    // miuix-nav 的路由是 @Serializable，需要序列化插件生成序列化器
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.10"
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
        }

        androidMain.dependencies {
            // Coil 3 在 Android 上通过 OkHttp 加载网络图
            implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.1")
        }
    }
}
