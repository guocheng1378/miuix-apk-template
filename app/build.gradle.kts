import java.io.File
import java.util.Properties

plugins {
    // AGP 9.x 已内置 Kotlin 支持，不能再显式应用 org.jetbrains.kotlin.android，
    // 否则 Gradle 配置阶段报 "Remove the 'org.jetbrains.kotlin.android' plugin"。
    id("com.android.application") version "9.3.2"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
}

dependencies {
    implementation(project(":shared"))
    implementation("androidx.activity:activity-compose:1.13.0")
}

android {
    namespace = "top.yukonga.miuixapptemplate"
    // miuix 0.9.4-rc01 AAR 要求 compileSdk >= 37
    compileSdk = 37

    defaultConfig {
        applicationId = "top.yukonga.miuixapptemplate"
        minSdk = 24
        targetSdk = 37
        versionCode = 2
        versionName = "1.0.2"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // 仅在提供了签名密钥（CI Secrets 或本地 local.properties）时才配置签名。
    // 未提供时 release 不做签名，产物为 app-release-unsigned.apk（需自行 zipalign + apksigner 才能安装/上架）。
    val localProps = Properties().apply {
        val lp = rootProject.file("local.properties")
        if (lp.exists()) lp.inputStream().use { load(it) }
    }
    fun signingProp(name: String): String? = System.getenv(name) ?: localProps.getProperty(name)

    val keystoreFile = signingProp("KEYSTORE_PATH")?.let { File(it) }
    val hasKeystore = keystoreFile != null && keystoreFile.exists()

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                storeFile = keystoreFile
                // 密钥库由 openssl pkcs12 -export 生成（无需 JDK），必须显式声明类型，
                // 否则 AGP 默认按 JKS 读取会失败。
                storeType = "PKCS12"
                storePassword = signingProp("KEYSTORE_PASS")
                keyAlias = signingProp("KEY_ALIAS")
                keyPassword = signingProp("KEY_PASSWORD")
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
