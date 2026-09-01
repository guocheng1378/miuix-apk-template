plugins {
    id("com.android.library") version "9.3.2"
    id("org.jetbrains.kotlin.multiplatform") version "2.4.10"
    id("org.jetbrains.compose") version "1.12.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
    // miuix-nav 的路由是 @Serializable，需要序列化插件生成序列化器
    id("org.jetbrains.kotlin.plugin.serialization") version "2.4.10"
}

kotlin {
    androidTarget()

    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.ui)

            // MIUIX 组件库（核心 + 图标）
            implementation("top.yukonga.miuix.kmp:miuix-ui:0.9.4-rc01")
            implementation("top.yukonga.miuix.kmp:miuix-icons:0.9.4-rc01")
            // 液态玻璃底栏所需
            implementation("top.yukonga.miuix.kmp:miuix-blur:0.9.4-rc01")
            // 可选模块按需打开：
            // implementation("top.yukonga.miuix.kmp:miuix-preference:0.9.4-rc01")
            // implementation("top.yukonga.miuix.kmp:miuix-squircle:0.9.4-rc01")
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

android {
    namespace = "top.yukonga.miuixapptemplate.shared"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
    }
}
