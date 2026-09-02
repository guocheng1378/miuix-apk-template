import java.io.File
import java.util.Properties

plugins {
    // AGP 9.x 已内置 Kotlin 支持，不能再显式应用 org.jetbrains.kotlin.android，
    // 否则 Gradle 配置阶段报 "Remove the 'org.jetbrains.kotlin.android' plugin"。
    id("com.android.application") version "9.3.2"
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.10"
}

// 版本号不再手工递增。取值优先级：显式 VERSION_CODE / VERSION_NAME > CI 派生值 > 本地兜底值。
// 本地兜底值就是自动化之前最后一次手工发版的值，这样在没有 CI 环境变量的机器上
// `gradle :app:assembleRelease` 依然可直接构建，且结果与改动前完全一致。
// （这段必须放在 plugins {} 之后：Gradle Kotlin DSL 只允许 buildscript/plugins 块作脚本头部。）
val defaultVersionCode = 2
val defaultVersionName = "1.0.2"

// GITHUB_RUN_NUMBER 是「单个 workflow 文件」内递增的运行编号，官方文档明确
// 「重跑同一次 run 该值不变」，所以同一个 tag 重复构建得到同一个 versionCode，可复现。
// 但它属于 workflow 而非仓库：若将来把发版挪到新的 workflow 文件，它会从 1 重新计数，
// 直接取用会让 versionCode 倒退（Google Play 拒收），因此与兜底值取 max。
val ciVersionCode = System.getenv("GITHUB_RUN_NUMBER")?.toIntOrNull()
    ?.let { maxOf(defaultVersionCode, it) }

// tag 触发的构建（GITHUB_REF_TYPE=tag）用 tag 名当 versionName，去掉约定的前导 "v"，
// 这样发版只需打 tag，不必再改本文件。workflow_dispatch / 分支 push 时为 null，
// 落回 defaultVersionName。
val ciVersionName = System.getenv("GITHUB_REF_NAME")
    ?.takeIf { System.getenv("GITHUB_REF_TYPE") == "tag" }
    ?.removePrefix("v")
    ?.takeIf { it.isNotEmpty() }

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
        versionCode = System.getenv("VERSION_CODE")?.toIntOrNull()
            ?: ciVersionCode
            ?: defaultVersionCode
        versionName = System.getenv("VERSION_NAME") ?: ciVersionName ?: defaultVersionName
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
