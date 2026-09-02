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
import ui.AppTheme
import ui.keyColorFor

/**
 * device-only 预览集合（玻璃 / squircle / 整 App 真玻璃路径）。
 *
 * 这些预览只放在 `preview` 包里，**不属于** JVM 截图回归的扫描范围——扫描只命中
 * `preview.settings`（见 `shared/build.gradle.kts` 的 `roborazzi { packages }`）。
 * 原因：miuix 的 AGSL 着色器用了 `layout(color)` 限定符，Robolectric 的
 * ShadowNativeRuntimeShader 内嵌 Skia 不认它，构造 RuntimeShader 时直接抛
 * `IllegalArgumentException("error: 'color' is not a valid layout qualifier")`，
 * 凡经过 squircle（Card）/ blur（液态底栏）/ 真玻璃路径的预览都会必红。
 *
 * 这套预览的真正用途是给 **emulator 冒烟 job**（`build-apk.yml`）当可渲染的
 * golden 参考来源；同一套代码在真机/模拟器上由那个 job 验证能正常启动与渲染。
 * 不要为了「让截图测试变绿」而在这里删玻璃预览——那是 Robolectric 的能力边界，
 * 不是 app 的问题。
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
 * 底栏浅色态（device-only 预览，不被 JVM 截图扫描）。
 *
 * `backdrop = null, isBlurActive = false` 让组件走 `Modifier.background(containerColor, pillShape)`
 * 回退分支；但 `IosLiquidGlassNavigationBar` 内部仍会无条件构造 `InteractiveHighlight`
 * 的 AGSL 着色器，Robolectric 下同样构造即抛异常。所以这条预览也只能在 emulator 冒烟里渲染。
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

// region 首页

/**
 * 首页浅色态（device-only 预览：见文件头说明，不被 JVM 截图扫描）。
 *
 * HomePage 内部的 `LaunchedEffect(loading)` / `LaunchedEffect(isRefreshing)` 初始值都是
 * false，所以预览期间不会有延时任务在跑，首帧即稳定态。注意 `HomePage` 用了 `Card`
 * （miuix-squircle），其 AGSL 着色器在 Robolectric 下构造即抛异常，所以这条预览只能在
 * emulator 冒烟 job 里渲染，不能在 JVM 截图回归里跑。
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
 * 整棵 App 树浅色态（device-only 预览，不被 JVM 截图扫描）。
 *
 * [App] 内部会自己调 `isRuntimeShaderSupported()`。该判断只看
 * `Build.VERSION.SDK_INT >= 33`，而真机/模拟器上返回 true，会真正走
 * `rememberLayerBackdrop()` + AGSL 着色器路径——正是 Robolectric 跑不起来的那段，
 * 所以交给 emulator 冒烟 job 验证。JVM 截图回归只覆盖 `preview.settings`（无 AGSL）。
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
