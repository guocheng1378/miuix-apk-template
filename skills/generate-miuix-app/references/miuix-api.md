# MIUIX 0.9.4-rc01 API 实测清单

下面的 import 路径与签名全部从本仓库 `App.kt`（672 行）的实际 import 与调用点抄出，
不是凭记忆写的。API 有疑义时按 `verification.md` 的四级核验法回到 sources jar 确认。

## import 路径速查

`top.yukonga.miuix.kmp.basic.*`：
`MiuixScrollBehavior`、`PullToRefresh`、`rememberPullToRefreshState`、`ScrollBehavior`、
`TopAppBar`、`Scaffold`、`BasicComponent`、`Card`、`Checkbox`、`Icon`、`NavigationItem`、
`SnackbarHost`、`SnackbarHostState`、`SnackbarResult`、`Slider`、`SmallTitle`、`Switch`、
`Text`、`Button`、`FloatingActionButton`

其它命名空间：

| 能力 | 路径 |
|---|---|
| 底部弹层 | `top.yukonga.miuix.kmp.overlay.OverlayBottomSheet` |
| 导航 | `top.yukonga.miuix.kmp.nav.core.{NavDisplay, rememberNavController, NavKey}` |
| 模糊/图层 | `top.yukonga.miuix.kmp.blur.{BlendColorEntry, BlurDefaults, LayerBackdrop, isRuntimeShaderSupported, layerBackdrop, rememberLayerBackdrop, textureBlur}` |
| 图标 | `top.yukonga.miuix.kmp.icon.{MiuixIcons, extended.Home, extended.Image, extended.Settings, extended.Back}` |
| 连续曲率圆角 | `top.yukonga.miuix.kmp.squircle.squircleSurface` |
| 偏好组件 | `top.yukonga.miuix.kmp.preference.{RadioButtonPreference, SwitchPreference}` |
| 主题 | `top.yukonga.miuix.kmp.theme.{ColorSchemeMode, MiuixTheme, ThemeController, ThemeColorSpec, ThemePaletteStyle}` |
| 滚动工具 | `top.yukonga.miuix.kmp.utils.overScrollVertical` |
| 图片 | `coil3.compose.SubcomposeAsyncImage`（Coil 3 在 `coil3.compose.*`，**不是** `androidx.compose.*`） |

## 主题

```kotlin
ThemeController(colorSchemeMode = mode, keyColor = keyColor ?: Color(0xFF3482FF))
MiuixTheme(controller)
```

`ColorSchemeMode`：`System` / `Light` / `Dark` / `MonetSystem` / `MonetLight` / `MonetDark`。
本模板的 `themeMode: Int` 映射是 `1=Light 2=Dark 3=MonetSystem else=System`。

`ui/Theme.kt` 提供：`LocalColorMode`、`AppTheme(colorMode, keyColor, paletteStyle, colorSpec)`、
`isInDarkTheme()`、`KeyColors`（7 项：Blue `0xFF3482FF` / Green / Purple / Yellow / Orange /
Pink / Teal）、`keyColorFor(index)`（**`index <= 0` 返回 `null`**，否则取 `index-1`——
`0` 是「跟随默认」而不是「第一个色」）。

## 导航（miuix-nav）

```kotlin
@Serializable
sealed interface Route : NavKey {
    data object Home : Route
    data object Image : Route
    data object Settings : Route
    data class Detail(val id: Int) : Route
}
```

- `rememberNavController<Route>(Route.Home)` + `NavDisplay { entry<Route.X> { ... } }`
- `push` / `pop` / `replace`
- `Route` 必须是 `@Serializable sealed interface Route : NavKey`——**闭式多态**，
  不需要 `SerializersModule`。写成 `abstract class` 或漏 `@Serializable` 都会在运行期炸。

## 滚动与 TopAppBar

大标题折叠：`MiuixScrollBehavior()` 传给 `TopAppBar(scrollBehavior = ...)` 即可，
miuix `Scaffold` 内部已接管滚动。

> **不要**手写 `Modifier.nestedScroll(scrollBehavior.nestedScroll.connection)`——
> miuix 的 `ScrollBehavior` 没有暴露 `nestedScroll.connection`，写了直接编译失败。
> 同理，`PullToRefresh` 包裹 `LazyVerticalGrid` 时滚动仍交给 miuix `Scaffold`。

`Scaffold(topBar / bottomBar / floatingActionButton / snackbarHost)`。

## 模糊与液态玻璃

```kotlin
val backdrop = if (isRuntimeShaderSupported()) rememberLayerBackdrop() else null
```

`isRuntimeShaderSupported()` 为假（Android 12 以下）时 `backdrop == null`，
**必须**降级为纯色 / squircle 并在 UI 上给提示。工程 `minSdk = 24` 而 blur 模块要求 33，
靠 Manifest 的 `tools:overrideLibrary` 放行，所以低版本真机是能装上的——降级分支不是可选项。

底栏模糊实测参数：

```kotlin
textureBlur(
    backdrop = backdrop,
    shape = ...,
    blurRadius = 25f,
    colors = BlurDefaults.blurColors(
        blendColors = listOf(BlendColorEntry(surface.copy(alpha = 0.8f)))
    )
)
```

`LiquidButton` 用 `squircleSurface(color, corner)` + `textureBlur(..., blurRadius = 18f, ...)`。

`miuix-squircle`：`Modifier.squircleSurface(color, cornerRadius)` / `squircleBackground` /
`squircleBorder`（不支持 RuntimeShader 时回退 `RoundedCornerShape`）。

## 底栏组件真实签名

```kotlin
@Composable
fun IosLiquidGlassNavigationBar(
    items: List<NavigationItem>,
    selectedIndex: Int,
    onItemClick: (Int) -> Unit,
    backdrop: LayerBackdrop?,
    isBlurActive: Boolean,
    modifier: Modifier = Modifier,
    badge: (Int) -> (@Composable () -> Unit)? = { null },
)
```

来自改编 Kyant0/AndroidLiquidGlass（**Apache-2.0**），组合 LayerBackdrop + textureBlur +
Highlight + 设备倾斜传感器。本仓库内的实现文件与行数（用于判断改动成本）：

| 文件 | 行数 |
|---|---|
| `LiquidGlassNavigationBar.kt` | 581 |
| `Lens.kt` | 226 |
| `DampedDragAnimation.kt` | 217 |
| `InnerShadow.kt` | 162 |
| `InteractiveHighlight.kt` | 118 |
| `CombinedBackdrop.kt` | 46 |
| `Vibrancy.kt` | 18 |

## 偏好与控件

- `RadioButtonPreference(title, selected, onClick)`——默认
  `radioButtonLocation = Start`
- `SwitchPreference(checked, onCheckedChange, title)`
- 两者均基于 `BasicComponent`，自带 `Role.RadioButton` / `Role.Switch`
- `BasicComponent(title, summary, modifier, startAction, endActions, onClick)`
- `Checkbox(state = ToggleableState, onClick)`、`Slider`、`Card`、`SmallTitle`、`Switch`、
  `Text`、`Button`、`FloatingActionButton`
- `SnackbarHost` / `SnackbarHostState` / `SnackbarResult`
- `OverlayBottomSheet(show, title, onDismissRequest)`
- `PullToRefresh(isRefreshing, onRefresh, pullToRefreshState, topAppBarScrollBehavior)`
  + `rememberPullToRefreshState()`
- `Icon` 用 `top.yukonga.miuix.kmp.basic.Icon`，**不是** `androidx.compose.foundation.Icon`
- `MiuixIcons` 的 extended 图标要单独 import：
  `top.yukonga.miuix.kmp.icon.extended.{Home, Image, Settings, Back}`

## 图片（Coil 3）

```kotlin
SubcomposeAsyncImage(
    model = url,
    contentDescription = ...,
    modifier = ...,
    contentScale = ...,
    loading = { ... },
    error = { ... },
)
```

`AsyncImage` 没有 `loading` / `error` 插槽，要用 `SubcomposeAsyncImage`。
网络图必须 `coil-network-okhttp` 在 androidMain + `INTERNET` 权限。

## App.kt 的 composable 清单

`App(prefs: AppPrefs)`、`HomePage`、`SwipeToDeleteItem`、`ImagePage`、`SettingsPage`、
`DetailPage`、`LiquidButton`。

详情页回显图片与图片页共用 `seed`（`picsum.photos/seed/$id/...`），无需改 `Route`。

左滑删除需自写 foundation `draggable`——MIUIX 0.9.4-rc01 **没有**内置 SwipeToDismiss。
列表删除用稳定 id（`filter { it != id }`），不要按值删 `items - i`。
