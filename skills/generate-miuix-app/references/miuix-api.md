# MIUIX 0.9.4-rc01 API 实测清单

下面的 import 路径与签名从本仓库 `App.kt` 的实际 import 与调用点抄出，并逐个回到
miuix 0.9.4-rc01 **全部 7 个模块**的 sources jar（`miuix-ui` / `miuix-icons` /
`miuix-blur` / `miuix-nav` / `miuix-preference` / `miuix-squircle` / `miuix-core`，
共 325 个 `.kt`）核对过，标注的 `文件:行号` 即 jar 内位置。API 有疑义时按
`verification.md` 的四级核验法确认。截至本次核对，**本文没有遗留「未核实」条目**；
以后新增若还没逐个取签名，必须显式标「**未核实**」（意思是没抄完，不是查不到），
不要当结论用。唯一的取证范围限制：`top.yukonga.miuix.kmp.shader` 模块**不在这 7 个
sources jar 里**，所以 `isRuntimeShaderSupported()` / `RuntimeShader` 在本文只能标到
`miuix-blur` 的转调点，看不到规范实现（详见「模糊与液态玻璃」节）。

## import 路径速查

`top.yukonga.miuix.kmp.basic.*`（以下名字**全部**在 `miuix-ui` sources jar 中实证存在）：

- 滚动/栏：`MiuixScrollBehavior`、`ScrollBehavior`、`TopAppBar`、`SmallTopAppBar`、
  `TopAppBarState`、`rememberTopAppBarState`、`TopAppBarDefaults`、`Scaffold`
- 下拉刷新：`PullToRefresh`、`rememberPullToRefreshState`、`PullToRefreshState`
- 容器/排版：`BasicComponent`、`Card`、`SmallTitle`、`Text`、`Icon`、`HorizontalDivider`、
  `VerticalDivider`
- 控件：`Button`、`FloatingActionButton`、`IconButton`、`Switch`、`Checkbox`、`RadioButton`、
  `Slider`、`TextField`
- 底栏：`NavigationBar`、`NavigationBarItem`、`NavigationItem`、`NavigationBarDisplayMode`
- 弹层数据：`DropdownItem`、`DropdownEntry`
- 提示条：`SnackbarHost`、`SnackbarHostState`、`SnackbarResult`（`SnackbarDuration` 也是 miuix
  自己的 `sealed interface`，**不是** `androidx.compose.material3` 的同名类型）

其它命名空间：

| 能力 | 路径 |
|---|---|
| 底部弹层/对话框 | `top.yukonga.miuix.kmp.overlay.{OverlayBottomSheet, OverlayDialog}` |
| 导航 | `top.yukonga.miuix.kmp.nav.core.{NavDisplay, NavController, rememberNavController, NavEntryBuilder, NavKey}` |
| 模糊/图层 | `top.yukonga.miuix.kmp.blur.{Backdrop, BlendColorEntry, BlurColors, BlurDefaults, LayerBackdrop, BackdropEffectScope, isRuntimeShaderSupported, layerBackdrop, rememberLayerBackdrop, textureBlur, progressiveTextureBlur, drawBackdrop}`；高光描边在子包 `top.yukonga.miuix.kmp.blur.highlight.{Highlight, HighlightStyle}` |
| 图标 | `top.yukonga.miuix.kmp.icon.MiuixIcons`（**在 `miuix-core`**，`MiuixIcons.kt:6`，是个只含 6 个空标记 object 的壳：`Basic`/`Light`/`Normal`/`Regular`/`Medium`/`Demibold`）+ 真正的图标是**扩展属性**，分两处：`top.yukonga.miuix.kmp.icon.basic.*`（7 个，**在 `miuix-ui`**：`ArrowRight`/`ArrowUpDown`/`Check`/`Close`/`Search`/`SearchCleanup`/`Sidebar`，走 `MiuixIcons.Basic.X`）与 `top.yukonga.miuix.kmp.icon.extended.*`（156 个，**在 `miuix-icons`**）。用 `MiuixIcons.Home` 必须**同时** import 这两条：`icon.MiuixIcons` + `icon.extended.Home`——图标是扩展属性，漏第二条就解析不到 |
| 连续曲率圆角 | `top.yukonga.miuix.kmp.squircle.{squircleSurface, squircleBackground, squircleClip, squircleBorder, absoluteSquircleSurface, absoluteSquircleBackground, absoluteSquircleClip, addSquircleRect, isSquircleEnabled, LocalSquircleEnabled, SquircleDefaults}`（全部已在 `miuix-squircle` sources jar 内实证，见「连续曲率圆角」节） |
| 偏好组件 | `top.yukonga.miuix.kmp.preference.{ArrowPreference, CheckboxPreference, OverlayDropdownPreference, OverlaySpinnerPreference, RadioButtonPreference, RangeSliderPreference, SliderPreference, SwitchPreference, WindowDropdownPreference, WindowSpinnerPreference}`（同模块另有 `top.yukonga.miuix.kmp.menu.*` / `top.yukonga.miuix.kmp.popup.*` 两个**兄弟包**，不随 `preference.*` 带进来，见「偏好组件」节末） |
| 主题 | `top.yukonga.miuix.kmp.theme.{ColorSchemeMode, MiuixTheme, ThemeController, ThemeColorSpec, ThemePaletteStyle}` |
| 滚动工具 | `top.yukonga.miuix.kmp.utils.overScrollVertical`（另有 `overScrollHorizontal` / `overScrollOutOfBound`） |
| 图片 | `coil3.compose.SubcomposeAsyncImage`（Coil 3 在 `coil3.compose.*`，**不是** `androidx.compose.*`） |

## 主题

```kotlin
ThemeController(colorSchemeMode = mode, keyColor = keyColor ?: Color(0xFF3482FF))
MiuixTheme(controller)
```

`ColorSchemeMode`：`System` / `Light` / `Dark` / `MonetSystem` / `MonetLight` / `MonetDark`。
本模板的 `themeMode: Int` 映射是 `1=Light 2=Dark 3=MonetSystem else=System`。

`ThemeController` 的 7 个属性**全是只读**，切主题只能 `remember(mode, keyColor) { ThemeController(...) }`
重建实例——详见下面「主题控制器」节。

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
- `push` / `pop` / `replace` / `popUntil`
- `Route` 写成 `@Serializable sealed interface Route : NavKey`——**闭式多态**，
  不需要 `SerializersModule`。写成 `abstract class` 会炸。
  严格说 `@Serializable` 只在经 `rememberNavBackStack` 持久化时才是硬要求
  （见下面「导航 API」节），但模板一律加上，别省。

## 滚动与 TopAppBar（本节是重灾区，照旧写法必错）

### 事实：miuix `Scaffold` **不接管滚动**

`Scaffold.kt:79` 的完整形参：

```kotlin
@Composable fun Scaffold(
    modifier: Modifier = Modifier,
    topBar: @Composable () -> Unit = {},
    bottomBar: @Composable () -> Unit = {},
    floatingActionButton: @Composable () -> Unit = {},
    floatingActionButtonPosition: FabPosition = FabPosition.End,
    floatingToolbar: @Composable () -> Unit = {},
    floatingToolbarPosition: ToolbarPosition = ToolbarPosition.BottomCenter,
    snackbarHost: @Composable () -> Unit = {},
    popupHost: @Composable () -> Unit = { MiuixPopupHost() },
    containerColor: Color = MiuixTheme.colorScheme.surface,
    contentWindowInsets: WindowInsets = WindowInsets.systemBars.union(WindowInsets.displayCutout),
    content: @Composable (PaddingValues) -> Unit,
)
```

**没有任何 `ScrollBehavior` 参数**。`Scaffold` 只做槽位排布 + 把 `innerPadding` 交给
`content`，它不参与 nested scroll 链。所以「`Scaffold` 内部已接管滚动」是错的——
不自己接线的话大标题折叠**收不到任何滚动事件**，页面照样能滚，只是 app bar 永远不动，
静态 grep 和编译都发现不了。

### 全库只有两个消费者

`grep -rn "ScrollBehavior"` 在全部 7 个模块的 sources jar 里只命中两个文件：

- `basic/TopAppBar.kt`（:111 `TopAppBar`、:182 `SmallTopAppBar`、:637 `TopAppBarLayout`）
- `basic/PullToRefresh.kt`（:109/:131/:176/:181/:632/:638/:653/:667/:706）

`TopAppBarLayout` 只**读** `scrollBehavior?.state?.heightOffset`（:645）、
`collapsedFraction`（:649），只**写** `heightOffsetLimit`（:659）——它自己不挂
`NestedScrollConnection`。而 `.nestedScroll(` 在整个 jar 里只有两处：
`PullToRefresh.kt:222` 和 `layout/BottomSheetContentLayout.kt:618`（后者是弹层内部自己的
connection，与 app bar 无关）。**`Scaffold` / `TopAppBar` 一处都没有。**

### 每页二选一，不能混

**A. 页面有下拉刷新语义** → 用 `PullToRefresh` 转发，它内部挂 connection 再转给 app bar：

```kotlin
val scrollBehavior = MiuixScrollBehavior()
PullToRefresh(
    isRefreshing = isRefreshing,
    onRefresh = { ... },
    modifier = Modifier.fillMaxSize(),
    topAppBarScrollBehavior = scrollBehavior,   // PullToRefresh.kt:176 建 connection，
) { LazyVerticalGrid(...) { ... } }             // :638-706 转发给 app bar
```

模板实证：`App.kt:336`（`HomePage`）、`App.kt:490`（`ImagePage`）。

**B. 页面没有下拉刷新** → 自己把 connection 挂在**滚动容器**上：

```kotlin
Column(
    modifier = Modifier
        .fillMaxSize()
        .nestedScroll(scrollBehavior.nestedScrollConnection),   // App.kt:561
) { ... }
```

模板实证：`App.kt:561`（`SettingsPage`，注释在 :559-560 说明原因）、`App.kt:632`（`DetailPage`，注释在 :630-631）。
`import androidx.compose.ui.input.nestedscroll.nestedScroll`（`App.kt:36`）——
`nestedScroll` 这个 Modifier 是 Compose 基础的，miuix 不提供同名封装。

**一个 `ScrollBehavior` 对应一个 `TopAppBar`。** 模板在 `App.kt:151` 顶层建一次，
再作为形参逐页传下去（`App.kt:179` 给 `TopAppBar`，`:264`/`:276`/`:280` 分发，
各页在 `:294`/`:477`/`:553`/`:622` 接收）。因为整个栈只有那一个 `TopAppBar`，
共享是对的；若改成每页各自渲染 `TopAppBar`，就必须每页各建一个，否则折叠状态会互相串。

> **属性名是 `nestedScrollConnection`，不是 `nestedScroll.connection`。**
> 后者在 miuix 里根本不存在，写了直接编译失败。`interface ScrollBehavior`
> （`TopAppBar.kt:422`）只有五个成员：`state` / `isPinned` / `snapAnimationSpec` /
> `flingAnimationSpec` / `nestedScrollConnection`（:454，KDoc 明写
> "should be attached to a [Modifier.nestedScroll]"）。

### 相关完整签名

```kotlin
// TopAppBar.kt:250，注意源码带 @Suppress("ComposableNaming")，函数名首字母大写是故意的
@Composable fun MiuixScrollBehavior(
    state: TopAppBarState = rememberTopAppBarState(),
    canScroll: () -> Boolean = { true },
    snapAnimationSpec: AnimationSpec<Float>? = spring(stiffness = 2500f),
    flingAnimationSpec: DecayAnimationSpec<Float>? = rememberSplineBasedDecay(),
): ScrollBehavior            // 内部返回 private ExitUntilCollapsedScrollBehavior（:474，isPinned = false）

// TopAppBar.kt:100
@Composable fun TopAppBar(
    title: String,
    modifier: Modifier = Modifier,
    color: Color = MiuixTheme.colorScheme.surface,
    titleColor: Color = MiuixTheme.colorScheme.onSurface,
    largeTitle: String = title,
    largeTitleColor: Color = MiuixTheme.colorScheme.onSurface,
    subtitle: String = "",
    subtitleColor: Color = MiuixTheme.colorScheme.onSurfaceVariantSummary,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    scrollBehavior: ScrollBehavior? = null,
    defaultWindowInsetsPadding: Boolean = true,
    titlePadding: Dp = TopAppBarDefaults.TitlePadding,
    navigationIconPadding: Dp = TopAppBarDefaults.NavigationIconPadding,
    actionIconPadding: Dp = TopAppBarDefaults.ActionIconPadding,
    bottomContent: @Composable () -> Unit = {},
)

// TopAppBar.kt:173 —— 同上，但【没有】 largeTitle / largeTitleColor；
// 它在 SideEffect 里把 state.pinnedBySmallTopAppBar = true 并把 heightOffsetLimit /
// heightOffset 归零（:189-197），即 SmallTopAppBar 会【反向改写】传进去的 state。
@Composable fun SmallTopAppBar(/* title … scrollBehavior: ScrollBehavior? = null … */)

// TopAppBar.kt:275（rememberSaveable，进程重建后保留偏移）
@Composable fun rememberTopAppBarState(
    initialHeightOffsetLimit: Float = -Float.MAX_VALUE,
    initialHeightOffset: Float = 0f,
    initialContentOffset: Float = 0f,
): TopAppBarState
```

`TopAppBarState`（:294）：`heightOffsetLimit`（:306）、`heightOffset`（:314，setter 里
`coerceIn(limit, 0f)`）、`contentOffset`、`collapsedFraction`（:341，只读派生）。
`TopAppBarDefaults`（:398）常量：`TitlePadding = 26.dp`、`NavigationIconPadding = 16.dp`、
`ActionIconPadding = 16.dp`、`CollapsedHeight = 52.dp`、`SmallTopAppBarCenterHeight = 50.dp`、
`LargeTitleBottomPadding = 4.dp`、`SubtitleBottomPadding = 8.dp`。

### `PullToRefresh` 完整签名（`PullToRefresh.kt:125`）

```kotlin
@Composable fun PullToRefresh(
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    pullToRefreshState: PullToRefreshState = rememberPullToRefreshState(),
    contentPadding: PaddingValues = PaddingValues(0.dp),
    topAppBarScrollBehavior: ScrollBehavior? = null,
    color: Color = PullToRefreshDefaults.color,
    circleSize: Dp = PullToRefreshDefaults.circleSize,
    refreshTexts: List<String> = PullToRefreshDefaults.refreshTexts,  // 4 条英文默认
    refreshTextStyle: TextStyle = PullToRefreshDefaults.refreshTextStyle,
    onPullProgress: ((Float) -> Unit)? = null,   // 观察 PullToRefreshState.fullDragProgress
    content: @Composable () -> Unit,
)

@Composable fun rememberPullToRefreshState(refreshThreshold: Float = 0.25f): PullToRefreshState
```

`PullToRefreshState`（:309）暴露 `fullDragProgress`（:353，`derivedStateOf`）。
`PullToRefreshDefaults`（:1026）。`PullToRefresh` 同时
`CompositionLocalProvider(LocalPullToRefreshState provides ...)`（:218 附近），
子树里可以直接读当前刷新状态而不必层层传参。

## 模糊与液态玻璃

### `rememberLayerBackdrop()` 返回**非空**

```kotlin
// blur/LayerBackdrop.kt:41
@Composable
fun rememberLayerBackdrop(
    graphicsLayer: GraphicsLayer = rememberGraphicsLayer(),
    onDraw: ContentDrawScope.() -> Unit = DefaultOnDraw,
): LayerBackdrop          // ← 非空
```

`class LayerBackdrop internal constructor(...) : Backdrop`（`:58`）——**构造器是 private 级别，
只能经 `rememberLayerBackdrop()` 拿**。`interface Backdrop`（`blur/Backdrop.kt:14`）是
`textureBlur` / `drawBackdrop` 实际接受的形参类型。

所以 `val backdrop: LayerBackdrop? = ...` 里的可空性**不是 API 给的降级分支，而是模板自己写的**：

```kotlin
// App.kt:123（模板真实写法）
val backdrop = if (isRuntimeShaderSupported()) rememberLayerBackdrop() else null
```

一旦声明成可空，就不能直接 `Modifier.textureBlur(backdrop = backdrop, ...)`——
`textureBlur` 的 `backdrop` 形参是**非空** `Backdrop`，传 `LayerBackdrop?` 编译失败。
正确写法是 `?.let`（模板 `App.kt:208-219` 就是这样）：

```kotlin
Modifier.then(
    backdrop?.let {
        Modifier.textureBlur(
            backdrop = it,
            shape = RectangleShape,
            blurRadius = 25f,
            colors = BlurDefaults.blurColors(
                blendColors = listOf(BlendColorEntry(MiuixTheme.colorScheme.surface.copy(alpha = 0.8f))),
            ),
        )
    } ?: Modifier,
)
```

录制侧同理：`App.kt:253` 写 `.then(backdrop?.let { Modifier.layerBackdrop(it) } ?: Modifier)`。

`isRuntimeShaderSupported()`（`blur/RuntimeShader.kt:31`）**只是 back-compat 转调**——整个
`blur/RuntimeShader.kt` 从 `:14` 起逐条标了「Back-compat re-export」，`:12` 以
`import top.yukonga.miuix.kmp.shader.isRuntimeShaderSupported as coreIsRuntimeShaderSupported`
别名引过来。规范定义在 `top.yukonga.miuix.kmp.shader` 模块，该模块**不在这 7 个 sources jar 里**
（`find -path "*kmp/shader*"` 为空），所以这里只能看到转调、看不到实现；squircle 的
`isSquircleEnabled()`（`LocalSquircleEnabled.kt:10`）import 的是同一个函数。

它为假（Android 12 以下）时**必须**降级为纯色 / squircle 并在 UI 上给提示。工程 `minSdk = 24`
而 blur 模块要求 33，靠 Manifest 的 `tools:overrideLibrary` 放行，所以低版本真机是能装上的——
降级分支不是可选项。

> 补充一条容易误判的事实：**消费侧本来就会自动降级**。
> `DrawBackdropModifier.kt:118` `val effectiveEnabled = enabled && isRuntimeShaderSupported()`。
> 也就是说"不支持 RuntimeShader 会崩"这个担心对 shader 调用本身不成立；
> 上面那些 `if` 分支真正解决的是**类型可空性**（要不要建那个 `LayerBackdrop` 实例）
> 和录制侧的浪费，别把它当成防崩溃的唯一手段。

### 接线规则（违反即首帧 native 崩溃）

`layerBackdrop` 是**录制**（把当前节点整棵子树录进一个 `RenderNode`），
`textureBlur`/`drawBackdrop` 是**重放**（`drawRenderNode` 建立真实父子边）。因此：

> **采样者 `N` 落在注册者 `M` 的子树内、且两者用同一个 `LayerBackdrop` 实例 ⇒ RenderNode
> 成环 ⇒ hwui `prepareTree` 无限递归 ⇒ 首帧 SIGSEGV。** 崩溃日志里一帧 Kotlin 都没有，
> 全是 512 层 `RenderNode::prepareTreeImpl`，极易误判成 GPU/模拟器问题。

- **一个实例只允许一个注册点**。`LayerBackdrop` 只有单个 `graphicsLayer` 和单个
  `layerCoordinates`，多处注册是静默的后写覆盖（`NavDisplay` 转场期两个 entry 同时存活
  会踩到），表现为采样错位/闪烁。
- 标准安全拓扑：**content 槽注册，`bottomBar` 槽采样**——miuix `Scaffold` 的
  `topBar`/`bottomBar`/content 是同一布局节点下独立的 `subcompose` 兄弟子节点。
- 页面内部想要玻璃元素（按钮等），**另起一个独立实例**并注册在纯装饰的**背景兄弟层**上
  （`Box(Modifier.matchParentSize().layerBackdrop(b))` + 子树内无任何消费者），
  本模板的 `buttonBackdrop` / `LiquidButtonBackdropLayer` 就是这个形状。
- 同一节点 `.layerBackdrop(X)` + `.drawBackdrop(Y)` 且 `X ≠ Y` 合法，上游
  `LiquidGlassNavigationBar` 自己就这么用。
- 多个消费者共享同一个被录制层是 DAG，无害。

完整机制与源码行号见 `pitfalls.md` G1；这条**静态 grep 判不出来**（祖先/后代是布局树
属性），只能靠 `build-apk.yml` 的 emulator 冒烟 job 兜。

### 模糊 Modifier 完整签名

```kotlin
// blur/TextureEffect.kt:29
fun Modifier.textureBlur(
    backdrop: Backdrop,                       // 非空
    shape: Shape,
    blurRadius: Float = BlurDefaults.BlurRadius,
    noiseCoefficient: Float = BlurDefaults.NoiseCoefficient,
    colors: BlurColors = BlurColors(),
    highlight: Highlight? = null,
    contentBlendMode: ComposeBlendMode = ComposeBlendMode.SrcOver,
    enabled: Boolean = true,
): Modifier

// blur/TextureEffect.kt:66  各向异性重载：把 blurRadius 换成 blurRadiusX + blurRadiusY（两个都无默认值）
fun Modifier.textureBlur(backdrop, shape, blurRadiusX: Float, blurRadiusY: Float, ...)

// blur/TextureEffect.kt:195 / :234  渐进模糊，多一个 gradient: ProgressiveBlur = ProgressiveBlur.Top，
// 且 noiseCoefficient 默认改用 BlurDefaults.ProgressiveNoiseCoefficient
fun Modifier.progressiveTextureBlur(backdrop, shape, blurRadius, gradient, noiseCoefficient, colors, highlight, contentBlendMode, enabled)

// blur/LayerBackdropModifier.kt:22  录制侧，一行实现：this then LayerBackdropElement(backdrop)
fun Modifier.layerBackdrop(backdrop: LayerBackdrop): Modifier

// blur/DrawBackdropModifier.kt:103  底层通用重放口
fun Modifier.drawBackdrop(
    backdrop: Backdrop,
    shape: () -> Shape,                                   // 注意是 lambda，不是 Shape
    effects: BackdropEffectScope.() -> Unit,
    highlight: (BackdropEffectScope.() -> Highlight?)? = null,
    layerBlock: (GraphicsLayerScope.() -> Unit)? = null,
    onDrawBehind: (DrawScope.() -> Unit)? = null,
    onDrawBackdrop: DrawScope.(drawBackdrop: DrawScope.() -> Unit) -> Unit = DefaultOnDrawBackdrop,
    onDrawSurface: (DrawScope.() -> Unit)? = null,
    onDrawFront: (DrawScope.() -> Unit)? = null,
    contentBlendMode: BlendMode = BlendMode.SrcOver,
    progressiveGradient: ProgressiveBlur? = null,
    enabled: Boolean = true,
): Modifier
```

`textureBlur` 是 `drawBackdrop` 的便捷封装（内部转调 `textureEffect`，`:104`/`:143`）。
`BackdropEffectScope` 是 `sealed interface`（`blur/BackdropEffectScope.kt:22`）。

### `BlurDefaults` 常量与颜色（`blur/BlurDefaults.kt`）

| 成员 | 值 / 签名 | 行号 |
|---|---|---|
| `BlurRadius` | `20f`（dp，内部按 density 转像素） | :150 |
| `NoiseCoefficient` | `0.0045f`（抗 banding 抖动，`0` 关闭） | :153 |
| `ProgressiveNoiseCoefficient` | `0f` | :156 |
| `MaxBlurRadius` | `150f` | :159 |
| `blurColors(...)` | `@Composable`，见下 | :170 |

```kotlin
@Composable fun BlurDefaults.blurColors(
    blendColors: List<BlendColorEntry> = emptyList(),   // 按顺序叠在模糊结果上
    brightness: Float = 0f,      // [-1, 1]，0 为不变
    contrast: Float = 1f,
    saturation: Float = 1f,
): BlurColors

data class BlurColors(blendColors, brightness, contrast, saturation)      // :24
data class BlendColorEntry(color: Color, mode: BlurBlendMode = BlurBlendMode.SrcOver)
data class Highlight(width: Dp = 0.8.dp, alpha: Float = 1f, style: HighlightStyle = HighlightStyle.Default)
```

`Highlight` 在**子包** `top.yukonga.miuix.kmp.blur.highlight`（`Highlight.kt:24`），
companion 里有 `GlassStrokeBigLight` 等主题预设。

`LiquidButton` 用 `squircleSurface(color, corner)` + `textureBlur(..., blurRadius = 18f, ...)`。

## 连续曲率圆角（miuix-squircle）

已在 `miuix-squircle` 0.9.4-rc01 sources jar 内逐个核实（`squircle/` 下 4 个公开文件 +
`internal/` 2 个）。包路径 `top.yukonga.miuix.kmp.squircle`。

**三组 API，每组「统一圆角」+「逐角」两个重载**，全部 `@Composable`（因为要读
`isSquircleEnabled()`）：

```kotlin
// SquircleBackground.kt
@Composable fun Modifier.squircleBackground(color: Color, cornerRadius: Dp,
    extension: Float = SquircleDefaults.Extension)                       // :51
@Composable fun Modifier.squircleBackground(color: Color,
    topStart: Dp, topEnd: Dp, bottomEnd: Dp, bottomStart: Dp,
    extension: Float = SquircleDefaults.Extension)                       // :69
@Composable fun Modifier.squircleClip(cornerRadius: Dp,
    extension: Float = SquircleDefaults.Extension)                       // :96
@Composable fun Modifier.squircleClip(topStart: Dp, topEnd: Dp,
    bottomEnd: Dp, bottomStart: Dp, extension: Float = ...)              // :112
@Composable fun Modifier.squircleSurface(color: Color, cornerRadius: Dp,
    extension: Float = SquircleDefaults.Extension)                       // :134
@Composable fun Modifier.squircleSurface(color: Color,
    topStart: Dp, topEnd: Dp, bottomEnd: Dp, bottomStart: Dp,
    extension: Float = ...)                                              // :152
```

`squircleSurface` = 背景 + 裁剪（内部 `rememberSquircleBrush(Color.White, ...)` 再叠
`fillColor`），`squircleBackground` 只填色，`squircleClip` 只裁剪。逐角顺序与
`RoundedCornerShape` 一致（`topStart/topEnd/bottomEnd/bottomStart`，**会**被
`LocalLayoutDirection` 翻转）。

另有 `absolute*` 三个同名前缀变体（`:182` / `:209` / `:233`），形参换成物理角
`topLeft/topRight/bottomRight/bottomLeft`，**不**随 `LocalLayoutDirection` 翻转——对应
`AbsoluteRoundedCornerShape` 的语义。只在角锚定到物理边（例如跟滑动方向绑定的转场揭示）
时才需要，普通页面用不上。

**描边确实存在**（旧版本这里撤回过，是错的）：

```kotlin
// SquircleBorder.kt
@Composable fun Modifier.squircleBorder(width: Dp, color: Color, cornerRadius: Dp,
    extension: Float = SquircleDefaults.Extension)                       // :30
@Composable fun Modifier.squircleBorder(width: () -> Dp, color: () -> Color,
    cornerRadius: Dp, extension: Float = ...)                            // :80
```

第二个重载收 lambda，配合 `animateDpAsState` / `animateColorAsState` 之类的动画值用，
避免每帧重组。只有统一圆角版，**没有**逐角 `squircleBorder`。

回退与开关：

```kotlin
// LocalSquircleEnabled.kt
val LocalSquircleEnabled = staticCompositionLocalOf { true }             // :18
@Composable @ReadOnlyComposable
fun isSquircleEnabled(): Boolean =
    LocalSquircleEnabled.current && isRuntimeShaderSupported()           // :27
```

即**默认开启**，且必须同时满足「CompositionLocal 没被关掉」+「平台支持 RuntimeShader」
（KDoc `SquircleBackground.kt:42-43` 明写「Android < API 33」时回退）。这个判断实际藏在
`private rememberSquircleBrush`（`:362`）里——`:370` 一句
`if (!LocalSquircleEnabled.current || !isRuntimeShaderSupported()) return null`，
上面每个 modifier 再 `?: return` 走普通圆角：`squircleBackground` 退化成
`background(color, RoundedCornerShape(...))`（`:78-80`）、`squircleClip` 退化成
`clip(RoundedCornerShape(...))`（`:119-120`）、`squircleSurface` 退化成
`clip(RoundedCornerShape(...)).background(color)`（`:161-163`）；`absolute*` 三支同构，只是换成
`AbsoluteRoundedCornerShape`（`:191-193` / `:216-217` / `:241-243`）。三个「统一圆角」重载本身
不含逻辑，只是把同一个 `cornerRadius` 摊成四角再转调逐角版（`:55` / `:99` / `:138`）。
`squircleBorder` 的回退分支另写一处：`:36-38` `if (!isSquircleEnabled()) return
this.border(width, color, RoundedCornerShape(cornerRadius))`。

结论：**低版本上 squircle 不会崩、不会透明，只是圆角变普通圆角**——视觉可用但角不是连续曲率。
写降级 UI 提示时别把这条和 blur 的崩溃混为一谈。

路径版 API（给 `clipPath` 这类不走 shader 管线的效果用）：

```kotlin
// SquirclePath.kt
object SquircleDefaults {                                                 // :14
    val Extension = 1.1f; val ExtensionMin = 1f; val ExtensionMax = 2f    // :17/:20/:23
}
fun Path.addSquircleRect(                                                 // :49
    width: Float, height: Float, cornerRadius: Float,
    extension: Float = SquircleDefaults.Extension,
    squircleEnabled: Boolean = true,
)
```

`extension` 是「角占位块 = cornerRadius 的多少倍」：`1.0` 就是普通圆弧，`1.1` 是默认的
连续曲率观感，超出 `1f..2f` 会被 `coerceIn` 夹住（`SquirclePath.kt:74`）。
`width`/`height` 非正数时**什么都不追加**（KDoc `:41-42` 明示，实现在 `:56` 直接 `return`），
单位是**像素**不是 Dp；`cornerRadius` 同样按像素收，并被夹到不超过短边一半——两个分支各夹一次：
非 squircle 分支在 `:58` 夹 `radius`，squircle 分支在 `:76` 夹 `cornerRadius * extension`
得到的 `tile`（`tile <= 0f` 时退化成 `addRect`，`:77-80`）。
`Path` 读不到 CompositionLocal，所以要手动把 `isSquircleEnabled()` 的结果传给
`squircleEnabled` 参数（`LocalSquircleEnabled.kt:15-16` 与 `SquirclePath.kt:37-39` 两处 KDoc
都明写这条要求）——`ListPopup.kt:623` 就是这么用的
（`:664` 调 `addSquircleRect`，`:668` 转发 flag）。
`addSquircleRect` 本身**不是** `@Composable`。

模板侧唯一调用点：`App.kt:56` import `squircleSurface`，`App.kt:738`
`Modifier.squircleSurface(MiuixTheme.colorScheme.primary.copy(alpha = 0.12f), corner)`
（位置参数即 `color, cornerRadius`），用作不支持 RuntimeShader 时 `LiquidButton` 的降级外观。

内部实现（`private`，不要引用）：`SquircleShaderBrush`（`SquircleBackground.kt:388`，
`:392` 构造 `RuntimeShader`，即 pitfalls G3 那条 Robolectric 崩溃点）、
`internal/AlphaImageBitmap.kt`、`internal/BakedSquircleSdf.kt`。

## 模板自带的液态玻璃底栏（非 miuix API）

> 这是**本仓库自己写的** composable，不是 miuix 提供的。miuix 官方底栏见下面
> 「底栏（`basic/NavigationBar.kt`）」节。

```kotlin
@Composable
fun IosLiquidGlassNavigationBar(
    items: List<NavigationItem>,
    selectedIndex: Int,
    onItemClick: (Int) -> Unit,
    backdrop: LayerBackdrop?,          // 可空，与 App.kt:123 那个 if 分支同源
    isBlurActive: Boolean,
    modifier: Modifier = Modifier,
    badge: (Int) -> (@Composable () -> Unit)? = { null },
)
```

来自改编 Kyant0/AndroidLiquidGlass（**Apache-2.0**），组合 LayerBackdrop + textureBlur +
Highlight + 设备倾斜传感器。本仓库内的实现文件与行数（用于判断改动成本）：

| 文件 | 行数 |
|---|---|
| `component/liquid/LiquidGlassNavigationBar.kt` | 581 |
| `component/liquid/Lens.kt` | 226 |
| `component/liquid/InnerShadow.kt` | 162 |
| `component/liquid/CombinedBackdrop.kt` | 46 |
| `component/liquid/Vibrancy.kt` | 18 |
| `component/animation/DampedDragAnimation.kt` | 217 |
| `component/animation/InteractiveHighlight.kt` | 118 |

（以上路径相对 `shared/src/commonMain/kotlin/`；注意后两个在 `animation/` 而非 `liquid/`。）

## 偏好组件（`miuix-preference`）

**没有 `PreferenceCategory` / `PreferenceGroup` / `PreferenceScreen`**——
`grep -rn "PreferenceCategory\|PreferenceGroup\|PreferenceScreen"` 在全部 7 个模块的
sources jar 里**全为空**。
分组只能用 `basic.SmallTitle` + `basic.Card` 手搭。

`preference` 包内全部 10 个公开组件，但**只有 9 个文件**——`RangeSliderPreference` 和
`SliderPreference` 共用 `SliderPreference.kt`（`:83` / `:212`），按文件名找会漏。
`ArrowPreference`、`CheckboxPreference`、`OverlayDropdownPreference`、`OverlaySpinnerPreference`、
`RadioButtonPreference`、`RangeSliderPreference`、`SliderPreference`、`SwitchPreference`、
`WindowDropdownPreference`、`WindowSpinnerPreference`。

> **形参顺序不统一，别跨组件复制粘贴位置参数**：`SwitchPreference` 是
> `(checked, onCheckedChange, title, ...)`，`RadioButtonPreference` / `CheckboxPreference` /
> `ArrowPreference` 是 `(title, ...)` 开头。一律用命名实参。

| 组件 | 必填（位置）形参 | 常用可选项（含默认值） | 行号 |
|---|---|---|---|
| `SwitchPreference` | `checked: Boolean`, `onCheckedChange: (Boolean) -> Unit`（**非空函数**）, `title: String` | `modifier`, `titleColor: BasicComponentColors`, `summary: String?`, `summaryColor`, `startAction: @Composable (()->Unit)?`, `endActions: @Composable RowScope.()->Unit = {}`, `bottomAction`, `switchColors`, `insideMargin`, `holdDownState = false`, `enabled = true` | :45 |
| `RadioButtonPreference` | `title: String`, `selected: Boolean`, `onClick: (()->Unit)?`（**必填但可空**） | `summary`, `colors: RadioButtonPreferenceColors`, `radioButtonColors`, `startAction`, `endActions: @Composable (RowScope.()->Unit)?`, `radioButtonLocation = RadioButtonLocation.Start`, `bottomAction`, `insideMargin`, `holdDownState`, `enabled` | :52 |
| `ArrowPreference` | `title: String` | `titleColor`, `summary`, `summaryColor`, `startAction`, `endActions = {}`, `bottomAction`, `insideMargin`, `onClick: (()->Unit)?`, `holdDownState`, `enabled` | :49 |
| `CheckboxPreference` | `title: String`, `checked: Boolean`, `onCheckedChange: ((Boolean)->Unit)?` | `titleColor`, `summary`, `summaryColor`, `checkboxColors`, `startAction`, `endActions`, `checkboxLocation = CheckboxLocation.Start`, `bottomAction`, `insideMargin`, `holdDownState`, `enabled` | :49 |
| `SliderPreference` | `value: Float`, `onValueChange: (Float) -> Unit` | `title: String?`, `valueText: String?`, `valueRange = 0f..1f`, `steps: Int = 0`, `onValueChangeFinished`, `reverseDirection = false`, `sliderHeight`, `sliderColors`, `hapticEffect`, `showKeyPoints = false`, `keyPoints: List<Float>?`, `magnetThreshold = 0.02f`, `insideMargin`, `onClick`, `enabled` | :83 |
| `OverlaySpinnerPreference` | **6 个重载**：`(items: List<DropdownItem>, selectedIndex: Int, title)` :60 / `(entry: DropdownEntry, title)` :115 / `(entries: List<DropdownEntry>, title)` :155 / 带 `dialogButtonString: String` 的对应三个 :288/:344/:386 | 六个共有：`summary`, `spinnerColors: DropdownColors`（**默认值随重载变**：非 dialog 三支
`:68/:122/:162` = `DropdownDefaults.dropdownColors()`，dialog 三支 `:298/:353/:395` =
`DropdownDefaults.dialogDropdownColors()`）, `startAction`, `bottomAction`, `insideMargin`, `enabled`, `showValue = true`, `renderInRootScaffold = true`, `onExpandedChange`。**随重载而变，别整表照抄**：`maxHeight: Dp?` 只在 :60/:115/:155（三个 `dialogButtonString` 版**没有** `maxHeight`，改为多一个 `popupModifier`）；`collapseOnSelection` 在 :115/:155/:288/:344/:386，**:60 没有**；`onSelectedIndexChange` 只在两个 `items` 版（:60/:288） |

剩下四个也已逐个取签名（**注意 `Dropdown` 与 `Spinner` 的数据类型不一样**）：

| 组件 | 重载与必填形参 | 备注 |
|---|---|---|
| `OverlayDropdownPreference` | 3 个：`(items: List<String>, selectedIndex: Int, title)` :58 / `(entry: DropdownEntry, title)` :113 / `(entries: List<DropdownEntry>, title)` :217 | 第一个收的是 **`List<String>`**，不是 `List<DropdownItem>`；**没有** `dialogButtonString` 重载；可选项 `dropdownColors: DropdownColors`、`maxHeight: Dp?`、`insideMargin`、`startAction`、`bottomAction` |
| `WindowDropdownPreference` | 3 个：`(items: List<String>, selectedIndex: Int, title)` :56 / `(entry: DropdownEntry, title)` :109 / `(entries: List<DropdownEntry>, title)` :211 | 同上，`List<String>`；**没有** `dialogButtonString` 重载 |
| `WindowSpinnerPreference` | 6 个：`(items: List<DropdownItem>, selectedIndex: Int, title)` :57 / `(entry: DropdownEntry, title)` :108 / `(entries: List<DropdownEntry>, title)` :146 / 带 `dialogButtonString: String` 的三个 :274/:328/:368 | `items` 版收 **`List<DropdownItem>`**（和 Dropdown 不同）；带 `dialogButtonString` 的重载还多一个 `popupModifier: Modifier`（`:280/:333/:373`）并**去掉
`maxHeight`**；`spinnerColors` 默认同样分两套——非 dialog `:65/:115/:153` 用
`DropdownDefaults.dropdownColors()`，dialog `:284/:337/:377` 用
`DropdownDefaults.dialogDropdownColors()` |
| `RangeSliderPreference` | 1 个：`(value: ClosedFloatingPointRange<Float>, onValueChange: (ClosedFloatingPointRange<Float>) -> Unit, ...)` :212（在 `SliderPreference.kt` 内） | `title: String?` 是**可选**的（默认 `null`），和 `SliderPreference` 一致；`endActions: @Composable (RowScope.()->Unit)?` 可为 `null`（`SwitchPreference` 那个是 `= {}` 非空）；`valueRange`/`steps`/`sliderHeight`/`sliderColors`/`hapticEffect`/`showKeyPoints`/`keyPoints`/`magnetThreshold = 0.02f`/`insideMargin` 与 `SliderPreference` 同名同默认值（`valueText: String?` 两边都有，不是 RangeSlider 独有）；**唯一的形参差集是
`reverseDirection`——`SliderPreference` 有（`:101`），`RangeSliderPreference` 没有**，
把 Slider 的调用表原样抄到 RangeSlider 上会直接编译不过 |

`dialogButtonString` 只存在于两个 **Spinner** 组件，**Dropdown 两个组件都没有**——
别把 Spinner 的六重载形态套到 Dropdown 上。

`Window*` 两个组件的形参增删规律与 `Overlay*` 完全一致（`items` 版有 `maxHeight` +
`onSelectedIndexChange` 但无 `collapseOnSelection`；`entry`/`entries` 版反之；
`dialogButtonString` 版无 `maxHeight`、多 `popupModifier`），差别只有一处：
**`Window*` 四个组件里都没有 `renderInRootScaffold`**，这个参数只在 `Overlay*` 家族上。

下拉数据类（`basic/Dropdown.kt`）：

```kotlin
data class DropdownEntry(val items: List<DropdownItem>, val enabled: Boolean = true)   // :319

data class DropdownItem(                                                                // :339
    val text: String,
    val enabled: Boolean = true,
    val selected: Boolean = false,
    val onClick: (() -> Unit)? = null,
    val icon: @Composable ((Modifier) -> Unit)? = null,   // 注意入参是 Modifier
    val summary: String? = null,
    val children: List<DropdownItem>? = null,             // 支持二级
)
```

同一个 `miuix-preference` 模块里还有两个**不在 `preference` 包下**的包，
`import top.yukonga.miuix.kmp.preference.*` 带不到它们，用到就得单独 import：
`top.yukonga.miuix.kmp.menu.*`（6 个公开组件，各 2 个重载：`OverlayDropdownMenu`
`OverlayDropdownMenu.kt:32/:73`、`OverlayIconDropdownMenu` `OverlayIconDropdownMenu.kt:28/:65`、
`OverlayIconCascadingDropdownMenu` `OverlayIconCascadingDropdownMenu.kt:32/:73`、
`WindowDropdownMenu` `WindowDropdownMenu.kt:32/:71`、`WindowIconDropdownMenu`
`WindowIconDropdownMenu.kt:28/:63`、`WindowIconCascadingDropdownMenu`
`WindowIconCascadingDropdownMenu.kt:32/:71`）与 `top.yukonga.miuix.kmp.popup.*`
（4 个：`OverlayDropdownPopup` `OverlayDropdownPopup.kt:35/:64`、`OverlayDropdownDialog`
同文件 `:115/:149`、`WindowDropdownPopup` `WindowDropdownPopup.kt:36/:63`、
`WindowDropdownDialog` 同文件 `:113/:145`；同文件里剩下的 `DropdownEntriesPopupContent`
（`DropdownEntriesContent.kt:23`）等标了 `internal`，import 不到）。10 个偏好组件里只有
`Overlay*` / `Window*` 那 4 个 Dropdown/Spinner 组件 import 了 `popup.*` 四个函数，
`menu.*` 在库内**零引用**——它是纯 app 侧 API，只有要自己搭下拉菜单 / 级联菜单时才需要 import。

## basic 控件参数表

```kotlin
// SmallTitle.kt:25  —— 分组标题就靠它
fun SmallTitle(text: String, modifier: Modifier = Modifier,
               textColor: Color = MiuixTheme.colorScheme.onBackgroundVariant,
               insideMargin: PaddingValues = SmallTitleDefaults.InsideMargin)

// Component.kt:59  主重载（title/summary 版）
fun BasicComponent(
    modifier: Modifier = Modifier,
    title: String? = null,                       // 可空
    titleColor: BasicComponentColors = BasicComponentDefaults.titleColor(),
    summary: String? = null,
    summaryColor: BasicComponentColors = BasicComponentDefaults.summaryColor(),
    startAction: @Composable (() -> Unit)? = null,
    endActions: @Composable (RowScope.() -> Unit)? = null,
    bottomAction: (@Composable () -> Unit)? = null,
    insideMargin: PaddingValues = BasicComponentDefaults.InsideMargin,
    onClick: (() -> Unit)? = null,
    onClickLabel: String? = null,
    role: Role? = null,                          // 无障碍：Role.Switch / Role.RadioButton 等
    holdDownState: Boolean = false,
    enabled: Boolean = true,
    interactionSource: MutableInteractionSource? = null,
)
// Component.kt:126  content 重载：无 title/summary，末位 content: @Composable ColumnScope.() -> Unit

// Card.kt:50  静态版
fun Card(modifier, cornerRadius: Dp = CardDefaults.CornerRadius,
         insideMargin: PaddingValues = CardDefaults.InsideMargin,
         colors: CardColors = CardDefaults.defaultColors(),
         content: @Composable ColumnScope.() -> Unit)
// Card.kt:87  可点版，多 pressFeedbackType: PressFeedbackType = None, showIndication = false,
//             holdDownState = false, onClick: (()->Unit)? = null, onLongPress: (()->Unit)? = null

// Button.kt:50  content 是 RowScope
fun Button(onClick: () -> Unit, modifier, enabled = true,
           cornerRadius: Dp = ButtonDefaults.CornerRadius, minWidth, minHeight,
           colors: ButtonColors = ButtonDefaults.buttonColors(), insideMargin,
           interactionSource: MutableInteractionSource? = null,
           indication: Indication? = LocalIndication.current,
           content: @Composable RowScope.() -> Unit)

// Switch.kt:66   onCheckedChange 可空
fun Switch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier,
           colors: SwitchColors = SwitchDefaults.switchColors(), enabled = true)

// Checkbox.kt:60 注意首参是 ToggleableState（androidx.compose.foundation.selection），不是 Boolean
fun Checkbox(state: ToggleableState, onClick: (() -> Unit)?, modifier,
             colors: CheckboxColors = CheckboxDefaults.checkboxColors(), enabled = true)

// RadioButton.kt:59
fun RadioButton(selected: Boolean, onClick: (() -> Unit)?, modifier,
                colors: RadioButtonColors = RadioButtonDefaults.radioButtonColors(), enabled = true)

// Slider.kt:88
fun Slider(value: Float, onValueChange: (Float) -> Unit, modifier, enabled = true,
           valueRange: ClosedFloatingPointRange<Float> = 0f..1f, steps: Int = 0,
           onValueChangeFinished: (() -> Unit)? = null, reverseDirection = false,
           height: Dp = SliderDefaults.MinHeight, colors: SliderColors = SliderDefaults.sliderColors(),
           hapticEffect = SliderDefaults.DefaultHapticEffect,
           showKeyPoints = false, keyPoints: List<Float>? = null, magnetThreshold = 0.02f)

// FloatingActionButton.kt:36  shape 默认 CircleShape，containerColor 默认 primary
fun FloatingActionButton(onClick, modifier, shape: Shape = CircleShape,
                         containerColor: Color = MiuixTheme.colorScheme.primary,
                         shadowElevation: Dp, minWidth: Dp, minHeight: Dp,
                         content: @Composable () -> Unit)

// IconButton.kt:40  注意没有 contentDescription / tint，内容自己放 Icon
fun IconButton(onClick, modifier, enabled = true, holdDownState = false,
               backgroundColor: Color = Color.Unspecified, cornerRadius: Dp,
               minHeight: Dp, minWidth: Dp, content: @Composable () -> Unit)

// Divider.kt:30 / :53
fun HorizontalDivider(modifier, thickness: Dp = DividerDefaults.Thickness, color = DividerDefaults.DividerColor)
fun VerticalDivider(modifier, thickness, color)
```

`Icon`（`basic/Icon.kt`）4 个重载：`imageVector` :53 / `bitmap` :88 / `painter` :124，
三者形参都是 `(内容, contentDescription: String?, modifier, tint: Color = LocalContentColor.current)`；
另有 `painter` + `tint: ColorProducer?` 版（:171，**`tint` 和 `contentDescription` 顺序颠倒**）。
用 `top.yukonga.miuix.kmp.basic.Icon`，**不是** `androidx.compose.foundation.Icon`。

`Text`（`basic/Text.kt`）4 个重载：`String`/`AnnotatedString` × `color: Color`（:90/:291）/
`color: ColorProducer`（:189/:397，此时 `color` 紧跟 `text` 排在 `modifier` 前）。
公共可选项含 `autoSize: TextAutoSize?`、`overflow`、`maxLines`、`minLines`、
`style: TextStyle = LocalTextStyles.current.main`。

### `TextField`（`basic/TextField.kt`，3 个重载）

```kotlin
// :82  新版 API，首参是 androidx.compose.foundation.text.input.TextFieldState（import 见 :25）
fun TextField(
    state: TextFieldState, modifier, insideMargin: DpSize = TextFieldDefaults.InsideMargin,
    colors: TextFieldColors = TextFieldDefaults.textFieldColors(),
    cornerRadius: Dp = TextFieldDefaults.CornerRadius,
    label: String = "", useLabelAsPlaceholder: Boolean = false,
    enabled = true, readOnly = false,
    inputTransformation: InputTransformation? = null,
    textStyle: TextStyle = MiuixTheme.textStyles.main,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    onKeyboardAction: KeyboardActionHandler? = null,
    lineLimits: TextFieldLineLimits = TextFieldLineLimits.Default,
    leadingIcon, trailingIcon, onTextLayout, interactionSource,
    cursorBrush: Brush = SolidColor(colors.borderColor),
    outputTransformation: OutputTransformation? = null, scrollState: ScrollState = rememberScrollState(),
)
// :188  (value: TextFieldValue, onValueChange, ...) —— 老式，带 keyboardActions / singleLine / maxLines / minLines / visualTransformation
// :294  (value: String, onValueChange, ...) —— 同上形参集
```

注意 `insideMargin` 是 **`DpSize`**（不是 `PaddingValues`），`label` 是 `String`（不是 composable）。

### 提示条（`basic/Snackbar.kt`）

```kotlin
@Composable fun SnackbarHost(state: SnackbarHostState, modifier: Modifier = Modifier,
                             canSwipeToDismiss: Boolean = true,
                             content: @Composable (SnackbarData) -> Unit = { Snackbar(it) })   // :272

suspend fun SnackbarHostState.showSnackbar(                                       // :183
    message: String, actionLabel: String? = null,
    withDismissAction: Boolean = false,
    duration: SnackbarDuration = SnackbarDuration.Short,
): SnackbarResult

enum class SnackbarResult { Dismissed, ActionPerformed }                          // :101
sealed interface SnackbarDuration {                                        // :80
    data object Short                                                      // :82
    data object Long                                                       // :85
    data object Indefinite                                                 // :88  一直显示直到手动关
    data class Custom(val durationMillis: kotlin.Long)                     // :91  init 里 require(> 0)
}
```

`SnackbarDuration` / `SnackbarResult` 都取自 `top.yukonga.miuix.kmp.basic`，**不是**
`androidx.compose.material3`——混用会类型不匹配。

### 弹层（`overlay/`）

```kotlin
// OverlayBottomSheet.kt:46
fun OverlayBottomSheet(
    show: Boolean, modifier, title: String? = null,
    startAction: @Composable (()->Unit)? = null, endAction: @Composable (()->Unit)? = null,
    backgroundColor: Color = BottomSheetDefaults.backgroundColor(),
    enableWindowDim: Boolean = true, cornerRadius: Dp, sheetMaxWidth: Dp,
    onDismissRequest: (()->Unit)? = null, onDismissFinished: (()->Unit)? = null,
    outsideMargin: DpSize, insideMargin: DpSize,          // 又是 DpSize
    defaultWindowInsetsPadding: Boolean = true, dragHandleColor: Color,
    allowDismiss: Boolean = true, enableNestedScroll: Boolean = true,
    renderInRootScaffold: Boolean = true,
    content: @Composable () -> Unit,
)
// OverlayDialog.kt:47  形参集与上面同族
```

## 底栏（`basic/NavigationBar.kt`）

```kotlin
// :73
@Composable fun NavigationBar(
    modifier: Modifier = Modifier,
    color: Color = MiuixTheme.colorScheme.surface,
    showDivider: Boolean = true,
    defaultWindowInsetsPadding: Boolean = true,
    mode: NavigationBarDisplayMode = NavigationBarDisplayMode.IconAndText,
    content: @Composable RowScope.() -> Unit,
)

// :143  条目在 RowScope 里，badge 槽在这里（不在 NavigationItem 上）
@Composable fun RowScope.NavigationBarItem(
    selected: Boolean, onClick: () -> Unit,
    icon: ImageVector, label: String,          // 直接给矢量和文本
    modifier: Modifier = Modifier, enabled: Boolean = true,
    badge: (@Composable () -> Unit)? = null,
)

// :283  浮动版：注意 content 不是 RowScope
@Composable fun FloatingNavigationBar(
    modifier: Modifier = Modifier,
    color: Color = MiuixTheme.colorScheme.surfaceContainer,   // 默认与 NavigationBar 不同
    cornerRadius: Dp = FloatingToolbarDefaults.CornerRadius,
    horizontalAlignment: Alignment.Horizontal = CenterHorizontally,
    horizontalOutSidePadding: Dp = FloatingNavigationBarDefaults.HorizontalOutSidePadding,
    shadowElevation: Dp = FloatingNavigationBarDefaults.ShadowElevation,
    showDivider: Boolean = false,                             // 默认与 NavigationBar 相反
    defaultWindowInsetsPadding: Boolean = true,
    content: @Composable () -> Unit,                          // ← 无 RowScope
)

// :384  配套条目，同样【不是】RowScope 扩展，别复用 RowScope.NavigationBarItem
@Composable fun FloatingNavigationBarItem(
    selected: Boolean, onClick: () -> Unit,
    icon: ImageVector, label: String,
    modifier: Modifier = Modifier, enabled: Boolean = true,
    badge: (@Composable () -> Unit)? = null,
)

// :541  数据类【只有 2 个参数】
@Immutable data class NavigationItem(val label: String, val icon: ImageVector)

// :518
enum class NavigationBarDisplayMode { IconAndText, IconOnly, IconWithSelectedLabel }
```

`NavigationItem` 没有 `selected` / `badge` / `onClick` 字段——选中态和回调在
`NavigationBarItem` 调用点传，badge 也只能走 `NavigationBarItem(badge = ...)`。
`NavigationBarDisplayMode` 另有 `LocalNavigationBarDisplayMode` compositionLocal 可覆盖
（`NavigationBar.kt:532`，`compositionLocalOf { IconAndText }`；`NavigationBar` 在 `:104`
把自身的 `mode` 形参下发给它）。**`FloatingNavigationBar` 没有 `mode` 形参**，要改浮动版的
显示模式只能自己 `CompositionLocalProvider(LocalNavigationBarDisplayMode provides ...)`。
两个栏目的条目不通用：`NavigationBar` 配 `RowScope.NavigationBarItem`（`:143`），
`FloatingNavigationBar` 配**非 RowScope** 的 `FloatingNavigationBarItem`（`:384`）——交叉
使用要么编译不过，要么布局不对。

> 官方就提供浮动底栏（`FloatingNavigationBar` :283 + `FloatingNavigationBarItem` :384），
> 所以下面「模板自带的液态玻璃底栏」不是唯一选择——要的是"浮起来一圈"的观感直接用官方这个，
> 只有需要真模糊/高光描边时才需要自写。
> 两个默认值对象不在同一个文件里，按文件名找会找不到：`FloatingNavigationBarDefaults`
> 在 `NavigationBar.kt:484`（`HorizontalOutSidePadding = 36.dp`、`ShadowElevation = 1.dp`、
> `HorizontalPadding = 12.dp`、`ItemSpacing = 12.dp`、`IconSize = 28.dp`、`IconPadding = 10.dp`）；
> 而 `cornerRadius` 的默认值 `FloatingToolbarDefaults.CornerRadius = 50.dp` 来自
> **另一个组件** `basic/FloatingToolbar.kt:84`（`:89`），`NavigationBar.kt` 里只是引用它。
> 配套的 `NavigationBarDefaults`（`NavigationBar.kt:457`）：`ItemHeight = 64.dp`、
> `IconSize = 26.dp`（注意与浮动版的 `28.dp` 不同）、`LabelFontSize = 12.sp`。

## 主题控制器（`theme/`）

```kotlin
// ThemeController.kt:217
@Stable class ThemeController(
    colorSchemeMode: ColorSchemeMode = ColorSchemeMode.System,
    lightColors: Colors = lightColorScheme(),
    darkColors: Colors = darkColorScheme(),
    keyColor: Color? = null,
    colorSpec: ThemeColorSpec = ThemeColorSpec.Spec2021,
    paletteStyle: ThemePaletteStyle = ThemePaletteStyle.TonalSpot,
    isDark: Boolean? = null,
)
```

`:226-232` 七个属性全是 `val x by mutableStateOf(...)`——**只读**，没有 setter。
切主题不能 `controller.colorSchemeMode = ...`，只能换构造参数重建实例，靠 `remember` 键控：

```kotlin
val controller = remember(mode, keyColor) { ThemeController(colorSchemeMode = mode, keyColor = keyColor) }
MiuixTheme(controller) { ... }
```

`MiuixTheme` 两个重载：`MiuixTheme(controller: ThemeController, textStyles, content)`
（`MiuixTheme.kt:24`）与 `MiuixTheme(colors: Colors, textStyles, content)`（`:54`）。
另有 `controller.currentColors()`（`ThemeController.kt:234` 起，`@Composable`）。

## 导航 API（`miuix-nav`）

```kotlin
// nav/core/NavController.kt:19
public class NavController(public val backStack: SnapshotStateList<NavKey>) {
    public fun push(key: NavKey)                                  // :21
    public fun pop(): Boolean                                     // :30  只剩根时返回 false
    public fun replace(key: NavKey)                               // :38  空栈则 add
    public fun popUntil(predicate: (NavKey) -> Boolean)           // :49  至少保留根
}

// :70  reified；单根要用父类型，如 rememberNavController<Route>(Route.Home)
@Composable public inline fun <reified T : NavKey> rememberNavController(vararg elements: T): NavController

// nav/core/NavDisplay.kt:948 / :979  两个重载
@Composable fun NavDisplay(
    backStack: NavBackStack,   // 或 navController: NavController（:979，onBack 默认 navController.pop()）
    modifier: Modifier = Modifier,
    onBack: () -> Unit = { backStack.removeLastOrNull() },
    transition: NavTransition = NavTransitions.MiuixDefault,
    effects: NavDisplayEffects = NavDisplayEffects(),
    content: NavEntryBuilder.() -> Unit,
)
// NavEntryBuilder（:105）+ inline fun <reified T : NavKey> entry(...)（:132）
```

`interface NavKey`（`NavKey.kt:26`）。**`@Serializable` 不是无条件必需**：只有经
`rememberNavBackStack`（`NavBackStack.kt:69`，`rememberSaveable` + `serializer<List<T>>()`）
持久化时才是硬要求；纯内存的 `navBackStackOf`（`:28`）不要求。模板 `Route.kt` 保守地给
每个子节点都标了 `@Serializable`。闭式多态（`sealed interface`）不需要 `SerializersModule`。

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
