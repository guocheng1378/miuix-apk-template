# liquid/ —— 液态玻璃组件源码（自包含）

本目录是**可直接拷进目标工程的成品源码**，不是文档。目标是让 agent 只凭 skill 就能从零搭出
液态玻璃底栏，不必先 clone 本模板仓库、也不必去上游仓库拼文件。

## 出处与许可

- 上游：Kyant0/AndroidLiquidGlass — <https://github.com/Kyant0/AndroidLiquidGlass>，**Apache-2.0**。
- 7 个 `.kt` 文件顶部第 1–6 行已自带出处头（`Copyright`、`SPDX-License-Identifier: Apache-2.0`、
  `package`、`// Adapted from Kyant0/AndroidLiquidGlass …`），**原样保留，不要删改、不要重排**。
  拷贝请用 `cp`，不要手抄——手抄会破坏逐字节一致性，也会丢掉出处头。
- 本模板仓库根有 `LICENSE`（Apache-2.0 正文，11342 字节）。

## 文件清单与落点

| 文件 | 行数 | `package` | 内容 |
|---|---|---|---|
| `component/liquid/LiquidGlassNavigationBar.kt` | 581 | `component.liquid` | 对外入口 `IosLiquidGlassNavigationBar`（:195） |
| `component/liquid/Lens.kt` | 226 | `component.liquid` | `BackdropEffectScope.lens()` 折射效果（:23） |
| `component/liquid/InnerShadow.kt` | 162 | `component.liquid` | `Modifier.innerShadow`（:48）、`InnerShadow`（:35） |
| `component/liquid/CombinedBackdrop.kt` | 46 | `component.liquid` | `CombinedBackdrop`（:24）、`rememberCombinedBackdrop`（:46） |
| `component/liquid/Vibrancy.kt` | 18 | `component.liquid` | `BackdropEffectScope.vibrancy()`（:12） |
| `component/animation/DampedDragAnimation.kt` | 217 | `component.animation` | 拖拽/按压动画 |
| `component/animation/InteractiveHighlight.kt` | 118 | `component.animation` | 高光描边 Modifier |

## 拷贝方式

保持 `component/liquid/` 与 `component/animation/` 两级相对路径，整棵落到目标工程的
`shared/src/commonMain/kotlin/` 下：

```
shared/src/commonMain/kotlin/component/liquid/*.kt
shared/src/commonMain/kotlin/component/animation/*.kt
```

**路径不能压平、包名不能改**：`LiquidGlassNavigationBar.kt:76-77` 按 `component.animation.*`
绝对路径 import 同批的两个动画文件，改包名要连改这两行 import。

## 必带随附片段：`ui.isInDarkTheme`

`LiquidGlassNavigationBar.kt:97` `import ui.isInDarkTheme`，指向本仓库
`shared/src/commonMain/kotlin/ui/Theme.kt:51`，而它又依赖同文件 `:18` 的 `LocalColorMode`。
**只拷本目录 7 个文件不解决这条，会编译失败。** 若目标工程没有 `ui/Theme.kt`，在
`shared/src/commonMain/kotlin/ui/Theme.kt` 补最小实现（抄自该文件 `:18`、`:51-55`）：

```kotlin
package ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.compositionLocalOf

val LocalColorMode = compositionLocalOf { 0 }

@Composable
fun isInDarkTheme(): Boolean = when (LocalColorMode.current) {
    1, 4 -> false
    2, 5, 6 -> true
    else -> isSystemInDarkTheme()
}
```

`LocalColorMode` 的取值语义（`1/4` 强制浅色、`2/5/6` 强制深色、其余跟随系统）照搬自
`ui/Theme.kt:51-55` 的分支，若目标工程自己有一套颜色模式枚举，按它的语义改写这个函数即可——
组件里只在 `:204` 读一次（`val isDark = isInDarkTheme()`），用于 `:414` 与 `:531` 两处的
阴影/描边 alpha。

> 不要改成"用 `MiuixTheme` 判断深浅色"：miuix 0.9.4-rc01 里"当前是否深色"这个值**存在但不可达**。
> 它在 `theme/ThemeController.kt:232`（`val isDark: Boolean? by mutableStateOf(isDark)`，
> 构造参数见 `:224`，消费见 `:237`、`:246` 的 `isDark ?: isSystemInDarkTheme()`），
> 但那是 `ThemeController` 实例上的属性，composable 侧没有任何公开入口能读到它：
> 主题相关的三个 Local 全是 `internal` —— `LocalColors`（`theme/Colors.kt:618`）、
> `LocalTextStyles`（`theme/TextStyles.kt:250`）、`LocalColorSchemeMode`
> （`theme/ThemeController.kt:266`）；公开的 `object MiuixTheme`
> （`theme/MiuixTheme.kt:72-95`）只暴露 `colorScheme` / `textStyles` / `colorSchemeMode`
> / `isDynamicColor`，没有 `isDark`。所以只能自带上面那个本地 helper。

## 非空 Backdrop 规则

`rememberLayerBackdrop()` 返回**非空** `LayerBackdrop`（`blur/LayerBackdrop.kt:41-49`，签名里没有可空）。
可空性来自降级写法本身——运行时不支持 RuntimeShader 时给 null：

```kotlin
// App.kt:123
val backdrop = if (isRuntimeShaderSupported()) rememberLayerBackdrop() else null  // LayerBackdrop?
```

而 `textureBlur` / `drawBackdrop` / `layerBackdrop` 的 backdrop 参数**一律非空**
（`blur/TextureEffect.kt:29` 与 `:66`、`blur/DrawBackdropModifier.kt:103`、`blur/LayerBackdropModifier.kt:22`）。
所以可空值必须 `?.let { … } ?: Modifier` 收口，直接传会编译失败：

```kotlin
// App.kt:253 注册
.then(backdrop?.let { Modifier.layerBackdrop(it) } ?: Modifier)
// App.kt:208-220 采样
backdrop?.let { Modifier.textureBlur(backdrop = it, …) } ?: Modifier
```

组件内部同样遵守：`LiquidGlassNavigationBar.kt:418` 先判 `if (isBlurActive && backdrop != null)`
再在 `:420` 传非空值（智能转换）；`:326` 用 `backdrop?.let { rememberCombinedBackdrop(it, tabsBackdrop) }`。

## RenderNode 成环硬规则（违反即 native 崩溃）

一个 `LayerBackdrop` 实例**只能有一个注册点**（一处 `layerBackdrop`），且**采样者不得是注册者的后代**。
同一实例被祖先注册、又被其后代采样，在 Android 上形成 RenderNode 父子环，`prepareTree` 无限递归
直接 native 崩溃（本仓库 `App.kt:124-126` 的注释原文即记录此事）。

落地写法：

- **content 槽注册 / bottomBar 槽采样**：`App.kt:249-253` 在 `Scaffold` 的 content lambda 里
  统一注册一次，`App.kt:201-245` 在 `bottomBar` 槽采样——两个槽是兄弟，不成环。
  转场期间两个 nav entry 同时存活也共用同一个注册节点（`App.kt:247-248` 注释）。
- **页面内玻璃另起独立实例**：`App.kt:127` 的 `buttonBackdrop` 与 `backdrop` 是两个
  `rememberLayerBackdrop()`；它注册在纯装饰的兄弟层上（`App.kt:680-682`
  `LiquidButtonBackdropLayer`），页面内的玻璃按钮采样它。见 `snippets/in-page-glass.kt.snippet`。
- **组件内部自带一个第三实例**：`LiquidGlassNavigationBar.kt:211` 自己
  `rememberLayerBackdrop()` 得到 `tabsBackdrop`，注册在 `:469-473` 那个 `.alpha(0f)` +
  `clearAndSetSemantics {}` 的隐藏兄弟 `Row` 上（它本身又采样外部 `backdrop`，`:475`），
  最后在 `:326` 与外部 `backdrop` 合成 `CombinedBackdrop` 供选中滑块采样（`:508-509`）。
  这一层是"滑块要透出标签"的技巧，**不要当成冗余代码删掉**。

## 依赖与平台要求

`shared/build.gradle.kts:45-48`（位于 `sourceSets { commonMain.dependencies { … } }`，块起于 `:39`）：

```kotlin
implementation("top.yukonga.miuix.kmp:miuix-ui:0.9.4-rc01")
implementation("top.yukonga.miuix.kmp:miuix-blur:0.9.4-rc01")
```

`miuix-blur` 与 `miuix-ui` 两者必带（组件 import 见各文件 `top.yukonga.miuix.kmp.blur.*` /
`basic.*` / `theme.*`）。Android 侧 `miuix-blur` 的 AAR 要求 **minSdk 33**
（AAR 内 `AndroidManifest.xml` 字面写 `android:minSdkVersion="33"`），
`isRuntimeShaderSupported()` 判的也是 `>= 33`——权威出处在 miuix-shader 的 Android actual
`androidMain/top/yukonga/miuix/kmp/shader/RuntimeShader.android.kt:18`
（`Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU`），miuix-blur 在
`blur/RuntimeShader.kt:31` 原样转出；本仓库 `shared/build.gradle.kts:119-121` 的注释与此同义。
所以低版本上 `backdrop` 走 null 分支、玻璃自动退化为普通底色——这是设计好的降级路径，
不是 bug，别为了"修模糊不生效"去改 minSdk。

## 接线示例

`snippets/` 下两个 `.kt.snippet`（沿用 `assets/` 里 `signing-config.gradle.kts.snippet` 的
`.snippet` 后缀约定，表示"片段"而非成品源码）：

- `snippets/app-wiring.kt.snippet` —— 双实例声明 + content 注册 + bottomBar 采样 + 组件调用。
  大部分内容按原样注释掉了，因为它依赖目标工程自己的 `Route` / `nav` / `selectedTab` 等状态，
  **整份不可直接编译**，只作接线参考。
- `snippets/in-page-glass.kt.snippet` —— 页面内玻璃按钮（兄弟层注册 + `textureBlur` 叠在可点击
  元素上 + 不支持时退化 squircle）。这段是 `App.kt:673-761` 的两个完整 composable，
  **补上 import 即可整份粘贴**进目标工程。

## `utils.Platform` / `platform()` 的来源

`LiquidGlassNavigationBar.kt:95-96` import `top.yukonga.miuix.kmp.utils.{Platform, platform}`，
`:329-330` 用 `platform()` / `Platform.IOS` 决定 iOS 底部留白（`20.dp`）。这条已核实，不是猜测：

- 声明在 **miuix-core**（不在 miuix-ui）：`miuix-core/commonMain/top/yukonga/miuix/kmp/utils/Utils.kt:13`
  `enum class Platform { Android, IOS, Desktop, WasmJs, MacOS, Js }`，`:25` `expect fun platform(): Platform`。
- actual 分平台给出：`miuix-core/iosMain/…/utils/Utils.ios.kt:6` `= Platform.IOS`、
  `miuix-core-android/androidMain/…/utils/Utils.android.kt:22` `= Platform.Android`。
- **只声明 `miuix-ui` 一项也够用**，不必额外加 miuix-core 依赖：miuix-ui 的 Gradle 模块元数据把
  miuix-core 列为 **api** 传递依赖（`miuix-ui-0.9.4-rc01.module` 的 `metadataApiElements`；Android 侧
  `miuix-ui-android-0.9.4-rc01.module` 的 `androidApiElements-published` → `miuix-core` + `miuix-squircle`）。
  注意 POM 里 miuix-core 标的是 `scope=runtime`——Gradle 优先读 `.module` 元数据而非 POM，所以 api 级成立。
- miuix 自己的 `basic/NavigationBar.kt:59-60` 同样 import 这两个符号，并在 `:109`、`:297-298`
  （`Platform.IOS -> 36.dp`）使用，与本组件的用法同构。
