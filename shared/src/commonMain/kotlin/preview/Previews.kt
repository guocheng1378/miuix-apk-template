package preview

import androidx.compose.runtime.Composable
import androidx.compose.ui.tooling.preview.Preview
import component.liquid.IosLiquidGlassNavigationBar
import top.yukonga.miuix.kmp.basic.MiuixScrollBehavior
import top.yukonga.miuix.kmp.basic.NavigationItem
import top.yukonga.miuix.kmp.basic.SnackbarHostState
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Home
import top.yukonga.miuix.kmp.icon.extended.Image
import top.yukonga.miuix.kmp.icon.extended.Settings
import top.yukonga.miuixapptemplate.App
import top.yukonga.miuixapptemplate.AppPrefs
import top.yukonga.miuixapptemplate.HomePage
import top.yukonga.miuixapptemplate.SettingsPage
import ui.AppTheme
import ui.keyColorFor

/**
 * 关键可复用 composable 的预览集合，同时充当 roborazzi 截图回归的 golden 来源。
 *
 * 这里集中放在独立的 `preview` 包（而不是散进各业务文件），是为了让
 * `roborazzi { generateComposePreviewRobolectricTests { packages = listOf("preview") } }`
 * 一条配置就能限定扫描范围：既不会把第三方库（miuix / coil）自带的 @Preview 扫进来
 * 产生无关 golden，也不会因为后续拆分业务文件而漏掉预览。
 *
 * ## 为什么不用 @PreviewLightDark
 * 本项目的明暗不是走系统的 `Configuration.uiMode`，而是由 [AppTheme] 里的
 * `LocalColorMode` 自己驱动的（`isInDarkTheme()` 只读这个 CompositionLocal）。
 * `@PreviewLightDark` 翻的是 uiMode 的 night bit，在这里不生效，所以明暗各写一个函数、
 * 显式传 `colorMode = 1 / 2`。
 *
 * ## 为什么所有壳函数都是 public
 * 截图文件名由预览函数的 JVM 方法名推导。Kotlin 的 `internal` 顶层函数在 JVM 上会被
 * mangle 成 `名字$模块名`，这个后缀会直接泄进 golden 文件名，导致改名/换模块时基线全废。
 *
 * ## 为什么不预览 ImagePage / DetailPage
 * 这两个页面用 `coil3.compose.SubcomposeAsyncImage` 打 `https://picsum.photos/...`。
 * Robolectric 沙箱里没有网络，成功/失败/占位三态不确定，逐像素比对必然漂移。
 */

/** 预览用的假偏好：[App] 只要求一个可读写三个字段的 [AppPrefs]，不需要真持久化。 */
private class PreviewPrefs(
    override var themeMode: Int,
    override var keyColorIndex: Int,
    override var notificationsEnabled: Boolean,
) : AppPrefs

// region 液态玻璃底栏

/**
 * 底栏浅色态。
 *
 * `backdrop = null, isBlurActive = false` 是刻意的：这两个参数同时决定组件走
 * `drawBackdrop`（真采样模糊）还是 `Modifier.background(containerColor, pillShape)`
 * 回退分支。回退分支不依赖 GPU/着色器，在 Robolectric 的 layoutlib 下输出确定，
 * 适合当 golden；真玻璃路径交给下面的 App 级预览去覆盖。
 */
@Preview(name = "LiquidGlassNavigationBarLight", widthDp = 360, heightDp = 120)
@Composable
fun LiquidGlassNavigationBarLight() {
    AppTheme(colorMode = 1) {
        IosLiquidGlassNavigationBar(
            items = previewNavItems(),
            selectedIndex = 0,
            onItemClick = {},
            backdrop = null,
            isBlurActive = false,
        )
    }
}

/** 底栏深色态，selectedIndex = 2 让「选中胶囊」落在最后一项上，覆盖位移后的布局。 */
@Preview(name = "LiquidGlassNavigationBarDark", widthDp = 360, heightDp = 120)
@Composable
fun LiquidGlassNavigationBarDark() {
    AppTheme(colorMode = 2) {
        IosLiquidGlassNavigationBar(
            items = previewNavItems(),
            selectedIndex = 2,
            onItemClick = {},
            backdrop = null,
            isBlurActive = false,
        )
    }
}

/**
 * 与 App.kt 里实际底栏保持一致的三项。
 *
 * 做成 `@Composable fun` 而不是顶层 `val`：`MiuixIcons.Home` 这类图标在编译期是
 * `MiuixIcons` 的扩展属性 getter，虽然当前实现不是 composable，但把它放进组合上下文里
 * 求值可以兼容「将来 miuix 把图标改成 remember 缓存的 composable getter」，同时避免顶层
 * `val` 在类初始化阶段就构造 ImageVector（Compose 的矢量模型对象最好在组合期内创建）。
 */
@Composable
private fun previewNavItems(): List<NavigationItem> = listOf(
    NavigationItem("首页", MiuixIcons.Home),
    NavigationItem("图片", MiuixIcons.Image),
    NavigationItem("设置", MiuixIcons.Settings),
)

// endregion

// region 设置页

/**
 * 设置页浅色态：themeMode=1 让单选框选中「浅色」，keyColorIndex=0 走默认主题色，
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

// endregion

// region 首页

/**
 * 首页浅色态。
 *
 * HomePage 内部的 `LaunchedEffect(loading)` / `LaunchedEffect(isRefreshing)` 初始值都是
 * false，所以预览期间不会有延时任务在跑，首帧即稳定态。
 * `buttonBackdrop = null` 是刻意的：页面内的 LiquidButton 因此走非玻璃分支，不依赖
 * GPU/着色器，在 Robolectric 的 layoutlib 下输出确定，适合当 golden；
 * 真玻璃路径交给下面的 App 级预览去覆盖。
 */
@Preview(name = "HomePageLight")
@Composable
fun HomePageLight() {
    AppTheme(colorMode = 1) {
        HomePage(
            buttonBackdrop = null,
            snackbarHost = SnackbarHostState(),
            onOpenDetail = {},
            scrollBehavior = MiuixScrollBehavior(),
        )
    }
}

/** 首页深色态。 */
@Preview(name = "HomePageDark")
@Composable
fun HomePageDark() {
    AppTheme(colorMode = 2) {
        HomePage(
            buttonBackdrop = null,
            snackbarHost = SnackbarHostState(),
            onOpenDetail = {},
            scrollBehavior = MiuixScrollBehavior(),
        )
    }
}

// endregion

// region 整 App（真玻璃路径）

/**
 * 整棵 App 树浅色态。
 *
 * 与上面几组的区别：[App] 内部会自己调 `isRuntimeShaderSupported()`。该判断只看
 * `Build.VERSION.SDK_INT >= 33`，而 roborazzi 生成的测试默认 `@Config(sdk = ["[33]"])`，
 * 所以这里返回 true，会真正走 `rememberLayerBackdrop()` + AGSL 着色器路径。
 * 这一组是整套 golden 里唯一覆盖「真玻璃」的，也是最可能因 layoutlib 对 AGSL 支持
 * 不稳定而漂移的两条；如果它们反复变红，删掉这两个函数即可，其余六条不受影响。
 *
 * 主题由 [App] 自己从 [AppPrefs] 里读，所以外面不再包 [AppTheme]，只喂不同的 prefs。
 */
@Preview(name = "AppLight")
@Composable
fun AppLight() {
    App(prefs = PreviewPrefs(themeMode = 1, keyColorIndex = 0, notificationsEnabled = true))
}

/** 整棵 App 树深色态 + Monet 之外的自定义主题色（keyColorIndex=2）。 */
@Preview(name = "AppDark")
@Composable
fun AppDark() {
    App(prefs = PreviewPrefs(themeMode = 2, keyColorIndex = 2, notificationsEnabled = false))
}

// endregion
