package preview.settings

import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import top.yukonga.miuix.kmp.basic.MiuixScrollBehavior
import top.yukonga.miuixapptemplate.SettingsPage
import ui.AppTheme
import ui.keyColorFor

/**
 * JVM 截图回归真正扫描的包（`preview.settings`）。
 *
 * 这里只放**不含任何 AGSL 着色器**的预览：SettingsPage 只用 miuix-preference 与主题，
 * 走纯 Compose 绘制，能在 Robolectric（layoutlib）下正常光栅化。
 *
 * 凡是经过 squircle（Card）/ blur（液态底栏）/ 真玻璃路径的预览都不在这里——
 * miuix 的 AGSL 用了 `layout(color)` 限定符，Robolectric 内嵌的 Skia 不认，构造
 * RuntimeShader 即抛 `IllegalArgumentException`，见 `preview/Previews.kt` 文件头与其
 * `build.gradle.kts` 里 `roborazzi { packages = listOf("preview.settings") }` 的注释。
 * 那些预览放在 `preview` 包，由 emulator 冒烟 job 覆盖。
 */

/**
 * 设置页浅色态：themeMode=1 选中「浅色」，keyColorIndex=0 走默认主题色，
 * notifications=true 让开关处于打开态（开关两态的绘制差异是本页最有回归价值的部分）。
 */
@Preview(name = "SettingsPageLight")
@Composable
fun SettingsPageLight() {
    AppTheme(colorMode = 1) {
        SettingsPage(
            themeMode = 1,
            keyColorIndex = 0,
            notifications = true,
            onThemeChange = {},
            onKeyColorChange = {},
            onNotificationsChange = {},
            scrollBehavior = MiuixScrollBehavior(),
        )
    }
}

/** 设置页深色态 + 自定义主题色（keyColorIndex=3 经 [keyColorFor] 映射到具体色值）。 */
@Preview(name = "SettingsPageDark")
@Composable
fun SettingsPageDark() {
    AppTheme(colorMode = 2, keyColor = keyColorFor(3)) {
        SettingsPage(
            themeMode = 2,
            keyColorIndex = 3,
            notifications = false,
            onThemeChange = {},
            onKeyColorChange = {},
            onNotificationsChange = {},
            scrollBehavior = MiuixScrollBehavior(),
        )
    }
}
