package top.yukonga.miuixapptemplate

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.key
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import component.liquid.IosLiquidGlassNavigationBar
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import top.yukonga.miuix.kmp.basic.Button
import top.yukonga.miuix.kmp.basic.Card
import top.yukonga.miuix.kmp.basic.FloatingActionButton
import top.yukonga.miuix.kmp.basic.NavigationItem
import top.yukonga.miuix.kmp.basic.Scaffold
import top.yukonga.miuix.kmp.basic.Slider
import top.yukonga.miuix.kmp.basic.SmallTitle
import top.yukonga.miuix.kmp.basic.SnackbarHost
import top.yukonga.miuix.kmp.basic.SnackbarHostState
import top.yukonga.miuix.kmp.basic.Switch
import top.yukonga.miuix.kmp.basic.Text
import top.yukonga.miuix.kmp.basic.SnackbarResult
import top.yukonga.miuix.kmp.preference.RadioButtonPreference
import top.yukonga.miuix.kmp.preference.SwitchPreference
import top.yukonga.miuix.kmp.squircle.squircleSurface
import coil3.compose.SubcomposeAsyncImage
import ui.KeyColors
import ui.keyColorFor
import top.yukonga.miuix.kmp.blur.BlendColorEntry
import top.yukonga.miuix.kmp.blur.BlurDefaults
import top.yukonga.miuix.kmp.blur.LayerBackdrop
import top.yukonga.miuix.kmp.blur.isRuntimeShaderSupported
import top.yukonga.miuix.kmp.blur.layerBackdrop
import top.yukonga.miuix.kmp.blur.rememberLayerBackdrop
import top.yukonga.miuix.kmp.blur.textureBlur
import top.yukonga.miuix.kmp.icon.MiuixIcons
import top.yukonga.miuix.kmp.icon.extended.Home
import top.yukonga.miuix.kmp.icon.extended.Image
import top.yukonga.miuix.kmp.icon.extended.Settings
import top.yukonga.miuix.kmp.nav.core.NavDisplay
import top.yukonga.miuix.kmp.nav.core.rememberNavController
import top.yukonga.miuix.kmp.theme.ColorSchemeMode
import top.yukonga.miuix.kmp.theme.MiuixTheme
import top.yukonga.miuix.kmp.basic.Icon
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt
import top.yukonga.miuix.kmp.basic.BasicComponent
import top.yukonga.miuix.kmp.basic.Checkbox
import top.yukonga.miuix.kmp.basic.MiuixScrollBehavior
import top.yukonga.miuix.kmp.basic.PullToRefresh
import top.yukonga.miuix.kmp.basic.RadioButton
import top.yukonga.miuix.kmp.basic.ScrollBehavior
import top.yukonga.miuix.kmp.basic.TopAppBar
import top.yukonga.miuix.kmp.basic.rememberPullToRefreshState
import top.yukonga.miuix.kmp.icon.extended.Back
import top.yukonga.miuix.kmp.overlay.OverlayBottomSheet
import top.yukonga.miuix.kmp.theme.ThemeController
import top.yukonga.miuix.kmp.utils.overScrollVertical

/**
 * 入口：miuix-nav 页面栈导航（三 tab + 详情页，带返回手势/状态保存）、
 * 加载/空状态、FAB + Snackbar、暗色/Monet 主题切换（持久化）、液态玻璃底栏。
 */
@Composable
fun App(prefs: AppPrefs) {
    // 主题/主题色/通知偏好持久化：初始化读 prefs，运行中写入 prefs 跨重启保留。
    var themeMode by remember(prefs) { mutableStateOf(prefs.themeMode) }
    var keyColorIndex by remember(prefs) { mutableStateOf(prefs.keyColorIndex) }
    var notifications by remember(prefs) { mutableStateOf(prefs.notificationsEnabled) }
    val keyColor = keyColorFor(keyColorIndex)
    val controller = remember(themeMode, keyColor) {
        val mode = when (themeMode) {
            1 -> ColorSchemeMode.Light
            2 -> ColorSchemeMode.Dark
            3 -> ColorSchemeMode.MonetSystem
            else -> ColorSchemeMode.System
        }
        ThemeController(colorSchemeMode = mode, keyColor = keyColor ?: Color(0xFF3482FF))
    }
    val setThemeMode: (Int) -> Unit = { m -> themeMode = m; prefs.themeMode = m }
    val setKeyColorIndex: (Int) -> Unit = { i -> keyColorIndex = i; prefs.keyColorIndex = i }
    val setNotifications: (Boolean) -> Unit = { b -> notifications = b; prefs.notificationsEnabled = b }

    MiuixTheme(controller = controller) {
        // backdrop：页面内容层，只在 Scaffold content 槽注册一次，由 bottomBar（兄弟槽）采样。
        val backdrop = if (isRuntimeShaderSupported()) rememberLayerBackdrop() else null
        // buttonBackdrop：页面内液态按钮专用层。必须与 backdrop 是两个独立实例——
        // 同一实例若被祖先节点 layerBackdrop 注册、又被其后代 textureBlur 采样，
        // 会在 Android 上形成 RenderNode 父子环，prepareTree 无限递归直接 native 崩溃。
        val buttonBackdrop = if (isRuntimeShaderSupported()) rememberLayerBackdrop() else null
        val blurActive = backdrop != null
        val nav = rememberNavController<Route>(Route.Home)
        val snackbarHost = remember { SnackbarHostState() }
        val scope = rememberCoroutineScope()

        // 栈顶决定选中的 tab（详情页无选中，bottomBar 隐藏）
        val selectedTab by remember(nav) {
            derivedStateOf {
                when (val top = nav.backStack.lastOrNull()) {
                    is Route.Home -> 0
                    is Route.Image -> 1
                    is Route.Settings -> 2
                    else -> -1
                }
            }
        }
        val isTopTab = selectedTab >= 0

        // 整个导航栈共用一个 ScrollBehavior：TopAppBar 只此一个，栈顶页面决定标题。
        // 注意 miuix Scaffold 不接管滚动——每页必须自己接线：有下拉刷新的页面包
        // PullToRefresh(topAppBarScrollBehavior = ...)，没有的在滚动容器上写
        // Modifier.nestedScroll(scrollBehavior.nestedScrollConnection)。一个页面只用其中
        // 一条路，别两条都接（重复接线会让同一段滚动被两条 connection 分别处理）。
        val scrollBehavior = MiuixScrollBehavior()
        val topTitle by remember(nav) {
            derivedStateOf {
                when (nav.backStack.lastOrNull()) {
                    is Route.Home -> "首页"
                    is Route.Image -> "图片"
                    is Route.Settings -> "设置"
                    is Route.Detail -> "详情"
                    else -> "MIUIX"
                }
            }
        }
        val topLargeTitle by remember(nav) {
            derivedStateOf {
                when (val top = nav.backStack.lastOrNull()) {
                    is Route.Home -> "MIUIX 液态玻璃套壳"
                    is Route.Image -> "图集"
                    is Route.Settings -> "设置"
                    is Route.Detail -> "详情 #${top.id}"
                    else -> "MIUIX"
                }
            }
        }
        Scaffold(
            topBar = {
                TopAppBar(
                    title = topTitle,
                    largeTitle = topLargeTitle,
                    scrollBehavior = scrollBehavior,
                    navigationIcon = {
                        if (!isTopTab) {
                            Icon(
                                MiuixIcons.Back,
                                contentDescription = "返回",
                                modifier = Modifier.clickable { nav.pop() },
                            )
                        }
                    },
                )
            },
            floatingActionButton = {
                if (isTopTab) {
                    FloatingActionButton(
                        onClick = { scope.launch { snackbarHost.showSnackbar("已点击 FAB") } },
                    ) {
                        Text("+", fontSize = 22.sp, color = MiuixTheme.colorScheme.onPrimary)
                    }
                }
            },
            snackbarHost = { SnackbarHost(snackbarHost) },
            bottomBar = {
                if (isTopTab) {
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .padding(bottom = 16.dp)
                            .then(
                                backdrop?.let {
                                    Modifier.textureBlur(
                                        backdrop = it,
                                        shape = RectangleShape,
                                        blurRadius = 25f,
                                        colors = BlurDefaults.blurColors(
                                            blendColors = listOf(
                                                BlendColorEntry(MiuixTheme.colorScheme.surface.copy(alpha = 0.8f)),
                                            ),
                                        ),
                                    )
                                } ?: Modifier,
                            ),
                    ) {
                        IosLiquidGlassNavigationBar(
                            items = listOf(
                                NavigationItem("首页", MiuixIcons.Home),
                                NavigationItem("图片", MiuixIcons.Image),
                                NavigationItem("设置", MiuixIcons.Settings),
                            ),
                            selectedIndex = selectedTab,
                            onItemClick = { index ->
                                val target = when (index) {
                                    0 -> Route.Home
                                    1 -> Route.Image
                                    2 -> Route.Settings
                                    else -> Route.Home
                                }
                                if (nav.backStack.lastOrNull() != target) {
                                    nav.replace(target)
                                }
                            },
                            backdrop = backdrop,
                            isBlurActive = blurActive,
                        )
                    }
                }
            },
        ) { innerPadding ->
            // 页面内容统一在这里注册进 backdrop（只此一处）：bottomBar 位于 Scaffold 的兄弟槽位，
            // 采样它不会成环；转场期间两个 entry 同时存活也共用同一个注册节点，避免重复 recordLayer。
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .then(backdrop?.let { Modifier.layerBackdrop(it) } ?: Modifier),
            ) {
                NavDisplay(
                    navController = nav,
                    modifier = Modifier.fillMaxSize(),
                ) {
                    entry<Route.Home> {
                        HomePage(
                            buttonBackdrop = buttonBackdrop,
                            snackbarHost = snackbarHost,
                            onOpenDetail = { nav.push(Route.Detail(it)) },
                            scrollBehavior = scrollBehavior,
                        )
                    }
                    entry<Route.Image> { ImagePage(onOpenDetail = { nav.push(Route.Detail(it)) }, scrollBehavior = scrollBehavior) }
                    entry<Route.Settings> {
                        SettingsPage(
                            themeMode = themeMode,
                            keyColorIndex = keyColorIndex,
                            notifications = notifications,
                            onThemeChange = setThemeMode,
                            onKeyColorChange = setKeyColorIndex,
                            onNotificationsChange = setNotifications,
                            scrollBehavior = scrollBehavior,
                        )
                    }
                    entry<Route.Detail> {
                        DetailPage(id = it.id, onBack = { nav.pop() }, buttonBackdrop = buttonBackdrop, scrollBehavior = scrollBehavior)
                    }
                }
            }
        }
    }
}

/** 首页：说明卡 + 通用控件 + 状态演示 + 可点击/可左滑删除列表（push 到详情页） */
@Composable
fun HomePage(
    buttonBackdrop: LayerBackdrop?,
    snackbarHost: SnackbarHostState,
    onOpenDetail: (Int) -> Unit,
    scrollBehavior: ScrollBehavior,
) {
    var loading by remember { mutableStateOf(false) }
    var empty by remember { mutableStateOf(false) }
    var items by remember { mutableStateOf(List(10) { it }) }
    var showSheet by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    val ptrState = rememberPullToRefreshState()
    LaunchedEffect(loading) {
        if (loading) {
            delay(800)
            loading = false
        }
    }
    LaunchedEffect(isRefreshing) {
        if (isRefreshing) {
            delay(800)
            isRefreshing = false
        }
    }

    val scope = rememberCoroutineScope()
    // 左滑删除的删除动作：按稳定 id 移除，并提供 Snackbar 撤销（P0-4 / P0-5）
    fun deleteItem(id: Int) {
        items = items.filter { it != id }
        scope.launch {
            val result = snackbarHost.showSnackbar("已删除列表项 #$id", actionLabel = "撤销")
            if (result == SnackbarResult.ActionPerformed) {
                items = (items + id).sorted()
            }
        }
    }

    Box(Modifier.fillMaxSize()) {
        // 背景兄弟层：注册 buttonBackdrop，供本页内的液态按钮折射采样。
        // 它必须是纯装饰叶子层——子树里不能出现任何 backdrop 消费者，否则又成环。
        LiquidButtonBackdropLayer(buttonBackdrop, Modifier.matchParentSize())

        PullToRefresh(
            isRefreshing = isRefreshing,
            onRefresh = { isRefreshing = true },
            pullToRefreshState = ptrState,
            topAppBarScrollBehavior = scrollBehavior,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .overScrollVertical()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp)) {
                        Text("MIUIX 液态玻璃套壳")
                        Text("miuix-nav 页面栈 + TopAppBar 大标题折叠 + 下拉刷新 + 底部弹层 + 左滑删除。")
                    }
                }

                SmallTitle(text = "通用")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        val on = remember { mutableStateOf(true) }
                        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                            Text("深色模式")
                            Switch(checked = on.value, onCheckedChange = { on.value = it })
                        }
                        val progress = remember { mutableStateOf(0.5f) }
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text("进度：${"%.0f".format(progress.value * 100)}%")
                            Slider(value = progress.value, onValueChange = { progress.value = it })
                        }
                        LiquidButton("液态按钮", onClick = {}, backdrop = buttonBackdrop, modifier = Modifier.fillMaxWidth())
                    }
                }

                SmallTitle(text = "状态演示")
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(Modifier.fillMaxWidth(), Arrangement.SpaceBetween, Alignment.CenterVertically) {
                            Text("列表是否为空")
                            Switch(checked = empty, onCheckedChange = { empty = it })
                        }
                        LiquidButton(
                            text = if (loading) "加载中…" else "模拟加载",
                            onClick = { loading = true },
                            backdrop = buttonBackdrop,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        LiquidButton(
                            text = "打开底部弹层",
                            onClick = { showSheet = true },
                            backdrop = buttonBackdrop,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(
                            when {
                                loading -> "状态：加载中"
                                empty -> "状态：暂无数据"
                                else -> "状态：内容正常"
                            },
                        )
                    }
                }

                if (!empty) {
                    SmallTitle(text = "列表（左滑删除，点击进入详情）")
                    items.forEach { i ->
                        key(i) {
                            SwipeToDeleteItem(onDelete = { deleteItem(i) }) {
                                BasicComponent(
                                    title = "列表项 #$i",
                                    summary = "点击进入详情页 #$i",
                                    modifier = Modifier.fillMaxWidth().clickable { onOpenDetail(i) },
                                    startAction = {
                                        Box(
                                            Modifier
                                                .size(36.dp)
                                                .clip(CircleShape)
                                                .background(MiuixTheme.colorScheme.primary.copy(alpha = 0.2f)),
                                            contentAlignment = Alignment.Center,
                                        ) { Text("#$i") }
                                    },
                                    endActions = {
                                        Text("›", fontSize = 20.sp, color = MiuixTheme.colorScheme.onSurface.copy(alpha = 0.4f))
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    OverlayBottomSheet(
        show = showSheet,
        title = "底部弹层",
        onDismissRequest = { showSheet = false },
    ) {
        BasicComponent(title = "弹层项 A", summary = "点击关闭", onClick = { showSheet = false })
        BasicComponent(title = "弹层项 B", onClick = { showSheet = false })
    }
}

/**
 * 轻量左滑删除：基于 foundation 的 draggable 手势，左滑超过阈值触发 onDelete，否则回弹。
 * MIUIX 0.9.4-rc01 无内置 SwipeToDismiss，这里用原生手势实现等价效果。
 */
@Composable
fun SwipeToDeleteItem(onDelete: () -> Unit, content: @Composable () -> Unit) {
    var offsetX by remember { mutableStateOf(0f) }
    val maxOffset = 120f
    val reveal = ((-offsetX) / maxOffset).coerceIn(0f, 1f)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .offset { IntOffset(offsetX.roundToInt(), 0) }
            .draggable(
                orientation = Orientation.Horizontal,
                state = rememberDraggableState { delta ->
                    offsetX = (offsetX + delta).coerceIn(-maxOffset, 0f)
                },
                onDragStopped = {
                    if (offsetX < -maxOffset / 2) onDelete() else offsetX = 0f
                },
            ),
    ) {
        // 左滑时从右侧露出红色删除区，作为可滑动删除的视觉提示（P0-4）
        Box(
            modifier = Modifier
                .matchParentSize()
                .background(Color(0xFFE53935).copy(alpha = 0.12f + 0.88f * reveal)),
            contentAlignment = Alignment.CenterEnd,
        ) {
            Text("删除", color = Color.White, fontSize = 14.sp, modifier = Modifier.padding(end = 24.dp))
        }
        content()
    }
}

/** 图片页：图集网格（2 列），Coil 加载真图（带加载/失败占位），点击进入 miuix-nav 详情页 */
@Composable
fun ImagePage(onOpenDetail: (Int) -> Unit, scrollBehavior: ScrollBehavior) {
    var isRefreshing by remember { mutableStateOf(false) }
    val ptrState = rememberPullToRefreshState()
    LaunchedEffect(isRefreshing) {
        if (isRefreshing) {
            delay(800)
            isRefreshing = false
        }
    }
    PullToRefresh(
        isRefreshing = isRefreshing,
        onRefresh = { isRefreshing = true },
        pullToRefreshState = ptrState,
        topAppBarScrollBehavior = scrollBehavior,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SmallTitle(text = "图片（Coil 网络图）")
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.fillMaxWidth().weight(1f),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(12) { i ->
                    Card(
                        Modifier
                            .fillMaxWidth()
                            .height(120.dp)
                            .clickable { onOpenDetail(i) },
                    ) {
                        SubcomposeAsyncImage(
                            model = "https://picsum.photos/seed/$i/300/300",
                            contentDescription = "图集 #$i",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop,
                            loading = {
                                Box(
                                    Modifier
                                        .fillMaxSize()
                                        .background(MiuixTheme.colorScheme.surfaceContainer),
                                )
                            },
                            error = {
                                Box(
                                    Modifier.fillMaxSize(),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Text(
                                        "加载失败",
                                        fontSize = 12.sp,
                                        color = MiuixTheme.colorScheme.onSurface,
                                    )
                                }
                            },
                        )
                    }
                }
            }
        }
    }
}

/** 设置页：主题/主题色单选（RadioButtonPreference）+ 通知开关（SwitchPreference）+ 三态 Checkbox 演示 */
@Composable
fun SettingsPage(
    themeMode: Int,
    keyColorIndex: Int,
    notifications: Boolean,
    onThemeChange: (Int) -> Unit,
    onKeyColorChange: (Int) -> Unit,
    onNotificationsChange: (Boolean) -> Unit,
    scrollBehavior: ScrollBehavior,
) {
    var checkboxState by remember { mutableStateOf(ToggleableState.On) }
    Column(
        modifier = Modifier
            .fillMaxSize()
            // 本页不套 PullToRefresh，必须自己把 ScrollBehavior 的 connection 接到滚动容器上，
            // 否则大标题折叠收不到任何滚动事件（miuix Scaffold 不接管滚动，见 README「滚动接线」）。
            .nestedScroll(scrollBehavior.nestedScrollConnection)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SmallTitle(text = "主题")
        RadioButtonPreference("跟随系统", selected = themeMode == 0, onClick = { onThemeChange(0) })
        RadioButtonPreference("浅色", selected = themeMode == 1, onClick = { onThemeChange(1) })
        RadioButtonPreference("深色", selected = themeMode == 2, onClick = { onThemeChange(2) })
        RadioButtonPreference("动态取色 (Monet)", selected = themeMode == 3, onClick = { onThemeChange(3) })

        SmallTitle(text = "主题色")
        KeyColors.forEachIndexed { idx, (name, color) ->
            val index = idx + 1
            RadioButtonPreference(
                title = name,
                selected = keyColorIndex == index,
                onClick = { onKeyColorChange(index) },
                startAction = {
                    Box(
                        Modifier
                            .size(20.dp)
                            .clip(CircleShape)
                            .background(color),
                    )
                },
            )
        }

        SmallTitle(text = "其他")
        SwitchPreference(
            checked = notifications,
            onCheckedChange = onNotificationsChange,
            title = "启用通知",
            summary = if (notifications) "已开启" else "已关闭",
        )
        BasicComponent(
            title = "MIUIX 三态 Checkbox",
            summary = "演示 Checkbox 三态",
            modifier = Modifier.fillMaxWidth(),
            startAction = {
                Checkbox(
                    state = checkboxState,
                    onClick = {
                        checkboxState = when (checkboxState) {
                            ToggleableState.On -> ToggleableState.Off
                            ToggleableState.Off -> ToggleableState.On
                            ToggleableState.Indeterminate -> ToggleableState.On
                        }
                    },
                )
            },
        )
    }
}

/**
 * 详情页：从列表项 push 进来，顶层 TopAppBar 自带返回图标，
 * NavDisplay 自带边缘/系统返回手势。
 */
@Composable
fun DetailPage(id: Int, onBack: () -> Unit, buttonBackdrop: LayerBackdrop?, scrollBehavior: ScrollBehavior) {
    Box(Modifier.fillMaxSize()) {
        // 背景兄弟层：与首页同理，按钮只采样自己这层，绝不采样祖先注册的 backdrop
        LiquidButtonBackdropLayer(buttonBackdrop, Modifier.matchParentSize())

        Column(
            modifier = Modifier
                .fillMaxSize()
                // 本页不套 PullToRefresh，滚动事件要靠这条 connection 送到 TopAppBar，
                // 否则大标题折叠不生效（miuix Scaffold 不接管滚动）。
                .nestedScroll(scrollBehavior.nestedScrollConnection)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 回显图片页点进来的那一张（与图片页共用 seed，无需改 Route）
            Card(Modifier.fillMaxWidth()) {
                SubcomposeAsyncImage(
                    model = "https://picsum.photos/seed/$id/600/300",
                    contentDescription = "详情图 #$id",
                    modifier = Modifier.fillMaxWidth().height(160.dp),
                    contentScale = ContentScale.Crop,
                )
            }
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp)) {
                    Text("详情 #$id")
                    Text("这是 miuix-nav push 进来的页面：自带返回转场、边缘/系统返回手势，返回后列表状态保留。")
                }
            }
            // 折叠说明：原有内容不足一屏，Column 根本滚不起来，接了 connection 也看不到效果，
            // 所以这里补一段真正需要滚动的内容，同时把接线规则写进模板本身。
            SmallTitle(text = "大标题折叠怎么接上的")
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("miuix 的 Scaffold 只负责排布槽位并给出 innerPadding，不参与滚动接线：它的形参里没有 ScrollBehavior。")
                    Text("全库只有 TopAppBar 和 PullToRefresh 接受 ScrollBehavior。PullToRefresh 内部会把自己的 connection 挂在容器上，再转发给 topAppBarScrollBehavior。")
                    Text("本页没有下拉刷新语义，因此直接在滚动 Column 上写 Modifier.nestedScroll(scrollBehavior.nestedScrollConnection)。")
                    Text("已经包在 PullToRefresh 里的页面（首页、图片页）不要再重复接一次，一条页面只走一条接线路径。")
                }
            }
            LiquidButton(
                text = "返回",
                onClick = onBack,
                backdrop = buttonBackdrop,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * 液态按钮的背景源层：把 [buttonBackdrop] 注册在这层纯装饰的兄弟节点上，
 * 页面里的 [LiquidButton] 采样它来折射"按钮背后"的颜色。
 * 这里画的是两团低透明度的主题色渐变（primary / tertiaryContainer），
 * 只作折射源用，不额外铺满整页底色。
 */
@Composable
private fun LiquidButtonBackdropLayer(buttonBackdrop: LayerBackdrop?, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.then(buttonBackdrop?.let { Modifier.layerBackdrop(it) } ?: Modifier),
    ) {
        Box(
            Modifier
                .fillMaxWidth(0.75f)
                .fillMaxHeight(0.45f)
                .align(Alignment.TopStart)
                .padding(32.dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            MiuixTheme.colorScheme.primary.copy(alpha = 0.22f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )
        Box(
            Modifier
                .fillMaxWidth(0.7f)
                .fillMaxHeight(0.4f)
                .align(Alignment.BottomEnd)
                .padding(24.dp)
                .background(
                    Brush.radialGradient(
                        colors = listOf(
                            MiuixTheme.colorScheme.tertiaryContainer.copy(alpha = 0.18f),
                            Color.Transparent,
                        ),
                    ),
                ),
        )
    }
}

/**
 * 液态玻璃按钮：把 textureBlur 叠在可点击元素上，折射 [backdrop]（页面内按钮专用的
 * 背景兄弟层，见 [LiquidButtonBackdropLayer]）里的内容。注意这个 backdrop 必须是按钮
 * 的兄弟而非祖先，否则 RenderNode 成环会 native 崩溃；[backdrop] 为 null
 * （不支持 RuntimeShader）时退化为普通 squircle 按钮。
 */
@Composable
fun LiquidButton(
    text: String,
    onClick: () -> Unit,
    backdrop: LayerBackdrop?,
    modifier: Modifier = Modifier,
) {
    val corner = 28.dp
    Box(
        modifier = modifier
            // 不支持 RuntimeShader（无液态玻璃）时退化为 squircle 连续圆角，而非纯圆
            .then(
                if (backdrop != null) {
                    Modifier.clip(CircleShape)
                } else {
                    Modifier.squircleSurface(MiuixTheme.colorScheme.primary.copy(alpha = 0.12f), corner)
                },
            )
            .clickable(onClick = onClick)
            .then(
                backdrop?.let {
                    Modifier.textureBlur(
                        backdrop = it,
                        shape = CircleShape,
                        blurRadius = 18f,
                        colors = BlurDefaults.blurColors(
                            blendColors = listOf(
                                BlendColorEntry(MiuixTheme.colorScheme.primary.copy(alpha = 0.5f)),
                            ),
                        ),
                    )
                } ?: Modifier,
            )
            .padding(horizontal = 24.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = MiuixTheme.colorScheme.onPrimary)
    }
}