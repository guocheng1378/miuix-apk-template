import java.io.File

plugins {
    id("com.android.application") version "9.3.2"
    id("org.jetbrains.kotlin.android") version "2.4.10"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
}

dependencies {
    implementation(project(":shared"))
    implementation("androidx.activity:activity-compose:1.13.0")
}

android {
    namespace = "top.yukonga.miuixapptemplate"
    compileSdk = 35

    defaultConfig {
        applicationId = "top.yukonga.miuixapptemplate"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // 仅在提供了签名密钥（CI Secrets 或本地 local.properties）时才配置签名。
    // 未提供时，release 会回退到 AGP 自带的 debug 签名，仍能产出可安装的 APK。
    val keystorePath = System.getenv("KEYSTORE_PATH")
        ?: rootProject.file("local.properties").let { lp ->
            if (lp.exists()) {
                val p = java.util.Properties().apply { load(lp.inputStream()) }
                p.getProperty("KEYSTORE_PATH")
            } else null
        }
    val keystoreFile = keystorePath?.let { File(it) }
    val hasKeystore = keystoreFile != null && keystoreFile.exists()

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("KEYSTORE_PASS")
                    ?: java.util.Properties().let { p ->
                        rootProject.file("local.properties").takeIf { it.exists() }
                            ?.inputStream()?.use { p.load(it) }
                        p.getProperty("KEYSTORE_PASS")
                    }
                keyAlias = System.getenv("KEY_ALIAS")
                    ?: java.util.Properties().let { p ->
                        rootProject.file("local.properties").takeIf { it.exists() }
                            ?.inputStream()?.use { p.load(it) }
                        p.getProperty("KEY_ALIAS")
                    }
                keyPassword = System.getenv("KEY_PASSWORD")
                    ?: java.util.Properties().let { p ->
                        rootProject.file("local.properties").takeIf { it.exists() }
                            ?.inputStream()?.use { p.load(it) }
                        p.getProperty("KEY_PASSWORD")
                    }
            }
        }
    }

    buildTypes {
        release {
            // 模板默认关闭 R8 以保证首编通过；需要体积优化时打开并补充 proguard 规则。
            isMinifyEnabled = false
            if (hasKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}
