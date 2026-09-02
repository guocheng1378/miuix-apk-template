# MIUIX APK 模板（Compose Multiplatform）

![Build + emulator 冒烟](https://github.com/guocheng1378/miuix-apk-template/actions/workflows/build-apk.yml/badge.svg)
![Screenshot 回归](https://github.com/guocheng1378/miuix-apk-template/actions/workflows/test.yml/badge.svg)
![Dependency Review](https://github.com/guocheng1378/miuix-apk-template/actions/workflows/dependency-review.yml/badge.svg)

用 **MIUIX 组件库**（`top.yukonga.miuix.kmp:miuix-ui`）搭建原生 Android 界面并产出 Release APK 的通用脚手架：**配好签名 Secrets 才产出已签名 APK**，未配置时产出 `app-release-unsigned.apk`（需自行用 `apksigner` 对齐并签名后才能安装/发布）。

全流程托管在 GitHub：把仓库推上去 → 配置签名 Secrets（不配的话 CI 的签名校验一步会直接判失败，见下文）→ 打 `v*` tag（或手动触发）→ GitHub Actions 自动编译并签名 → 产物为 APK（可下载 / 打 tag 时自动建 Release）。

> 本机**无需**安装 JDK / Android SDK；构建与签名全部在 GitHub Actions（自带 JDK 21 + Android SDK，并由 `setup-gradle` 提供 Gradle）完成。

**当前状态**：签名发布链路**已跑通**——本仓库已配置正式签名 Secrets，最新已签名 Release 为 `v1.0.4`（APK Signature Scheme v2，可直接下载安装），见[已发布版本与产物校验](#已发布版本与产物校验)。
测试体系**已就位三套**且目前**全绿**：① emulator 冒烟（CI 模拟器安装启动 App，抓原生崩溃）；② JVM 截图回归（Robolectric 渲染预览，只扫不含 AGSL 的 `preview.settings` 包）；③ 依赖审查。详见[测试与验证现状](#测试与验证现状)。

## 能力清单（代码里实际有的）

- **悬浮液态玻璃底栏**：`miuix-blur` 的 `LayerBackdrop` / `textureBlur` / `Highlight` + 设备倾斜传感器（`rememberDeviceTilt`）组合成 `IosLiquidGlassNavigationBar`，实时折射背后画面；不支持 `RuntimeShader` 的设备自动降级为纯色底栏。
- **miuix-nav 页面栈**：三个顶层 tab（首页 / 图片 / 设置）+ 带参详情页 `Route.Detail(id)`，支持 push/pop/replace、边缘滑动返回、系统预测性返回手势、返回栈跨配置变更保存。
- **主题**：深/浅色与强调色切换（`ThemeController`），偏好经 `SharedPreferences` 持久化，重启保留。
- **大标题折叠 TopAppBar**：全栈共用一个 `MiuixScrollBehavior`，四页（首页 / 图片 / 设置 / 详情）都已接线，每页自己接（见[滚动接线](#滚动接线大标题折叠)）。
- **首页**：下拉刷新、左滑删除 + Snackbar 撤销、`OverlayBottomSheet` 底部弹层、FAB。
- **图片页**：`LazyVerticalGrid` + Coil 3 `SubcomposeAsyncImage`，带加载中/失败占位，点击进详情页回显该图。
- **设置页**：`miuix-preference` 的 `RadioButtonPreference`（主题/主题色）+ `SwitchPreference`（通知）。
- **edge-to-edge**、squircle 连续圆角降级、自定义启动图标。
- **静态原型**：`preview.html`（浏览器打开的 HTML 版式稿，不参与 Gradle 构建）。
- **CI 与发布**：Actions 编译 release APK → `apksigner verify` 校验签名 → 上传 artifact → `v*` tag 自动建 GitHub Release 附 APK。

## 技术栈（CI 端到端编译验证通过的组合）

| 组件 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`miuix-ui` + `miuix-icons` + `miuix-blur` + `miuix-nav` + `miuix-preference` + `miuix-squircle`） |
| Coil | `3.6.1`（`coil-compose` common + `coil-network-okhttp` android） |
| kotlinx-serialization | `1.11.0` |
| compileSdk / targetSdk | `37` |
| minSdk | `24` |
| JDK（CI） | `21`（Zulu） |
| Gradle | `9.7.1`（`gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`） |

> **compileSdk 必须是 37**：`miuix 0.9.4-rc01` 的 AAR 声明 `minCompileSdk=37`，低于 37 会直接构建失败。这是最容易忽略的硬性前提。

## 工程结构

```
miuix-apk-template/
├── settings.gradle.kts             # 无根 build.gradle.kts，插件/依赖版本写在各模块 build 脚本里
├── gradle.properties
├── gradle/wrapper/gradle-wrapper.properties   # 只提交 properties；gradlew 与 wrapper jar 未入库
├── preview.html                    # 浏览器里的 HTML 版式稿，不参与构建
├── shared/                         # KMP 库：commonMain 放 Compose UI
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/
│       ├── top/yukonga/miuixapptemplate/
│       │   ├── App.kt              # 页面 + 导航 + 主题
│       │   ├── AppPrefs.kt         # 偏好持久化接口（common）
│       │   └── Route.kt            # @Serializable 路由定义
│       ├── component/liquid/       # 液态玻璃底栏（改编自 Kyant0/AndroidLiquidGlass）
│       ├── component/animation/    # 按压形变 / 高光动效
│       └── ui/Theme.kt             # 主题色
├── app/                            # 纯 Android 应用模块
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── kotlin/top/yukonga/miuixapptemplate/
│       │   ├── MainActivity.kt
│       │   └── AndroidAppPrefs.kt  # AppPrefs 的 SharedPreferences 实现
│       └── res/...                 # 图标、主题、字符串
├── skills/generate-miuix-app/      # 自动生成同类 App 的 skill
└── .github/workflows/build-apk.yml # 自动构建 + 签名 + 签名校验 + 建 Release
```

UI 写在 `shared/src/commonMain/kotlin/top/yukonga/miuixapptemplate/App.kt`，
用 MIUIX 组件（`TopAppBar` / `Scaffold` / `Card` / `Switch` / `Slider` / `Button` / `Text`）+ `MiuixTheme` 主题。
把这段 Composable 换成你自己的界面即可。

## 本地构建（可选，需本机有 JDK 21 + Android SDK + Gradle 9.x）

仓库**没有提交** `gradlew` 和 `gradle/wrapper/gradle-wrapper.jar`（只有 `gradle-wrapper.properties`），
本地构建要么自行准备与 AGP 9.x 匹配的 Gradle 9.x，要么补交 wrapper jar。

```bash
gradle :app:assembleRelease
# 未提供密钥：app/build/outputs/apk/release/app-release-unsigned.apk（unsigned，不能直接安装）
# 提供密钥：  app/build/outputs/apk/release/app-release.apk
```

本地密钥走 `local.properties`（`KEYSTORE_PATH` / `KEYSTORE_PASS` / `KEY_ALIAS` / `KEY_PASSWORD`），
同名环境变量优先级更高。

## GitHub Actions 自动构建 + 签名

### 1. 生成签名密钥（只需一次）

**推荐：openssl 直接生成 PKCS12，不需要装 JDK**（本仓库 release 密钥就是这么产出来的）：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 10950 -nodes \
  -keyout key.pem -out cert.pem \
  -subj "/C=CN/O=myorg/CN=my-release"

openssl pkcs12 -export -inkey key.pem -in cert.pem -out release.p12 \
  -name mykey -passout pass:'<你的口令>'

# 转成单行 base64，作为 SIGNING_KEY 的值
base64 -w0 release.p12
```

用 PKCS12 时 `app/build.gradle.kts` 必须显式声明 `storeType = "PKCS12"`，
否则 AGP 按默认 JKS 读取会失败（模板已设好）。

**备选：本机有 JDK 时用 keytool**（产出 JKS，此时把 `storeType` 去掉或改成 `"JKS"`）：

```bash
keytool -genkeypair -v \
  -keystore release.keystore -keyalg RSA -keysize 2048 -validity 10000 \
  -alias mykey
base64 -w0 release.keystore
```

> ⚠️ keystore 与口令**必须自行异地备份**，且绝不能提交进仓库（`.gitignore` 已忽略 `*.jks` / `*.p12` / `*.keystore`）。
> 丢了它，这个 `applicationId` 就再也无法以覆盖升级的方式装到已装用户机上。

### 2. 在仓库配置 Secrets

`Settings → Secrets and variables → Actions → New repository secret`：

| Secret | 内容 |
|---|---|
| `SIGNING_KEY` | 上面 `base64 -w0 release.p12` 的输出（单行 base64 的 PKCS12 内容） |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | `mykey`（上面的 alias） |
| `KEY_PASSWORD` | 密钥密码 |

> 四个名字都要对上：workflow 把 `SIGNING_KEY` 解成 `keystore.p12`，再以 `KEYSTORE_PASS` / `KEY_ALIAS` / `KEY_PASSWORD` 三个环境变量传给 Gradle（`app/build.gradle.kts` 里的 `signingProp()` 先读环境变量、再读 `local.properties`）。
>
> 缺任何一个密钥时 AGP 干脆不配 signingConfig，产物是 **`app-release-unsigned.apk`**——**不会**回退成 debug 签名的可安装包。而且本仓库 workflow 的 **Verify APK signature** 一步会把未签名产物直接判为 CI 失败，所以 fork 之后要么配齐四个 Secrets，要么放宽那一步，否则分支上的构建永远是红的。这种 unsigned APK 若真要安装/上架，需自行 `zipalign` + `apksigner sign`。

### 3. 构建命令与签名判定（真实形态）

- CI 用 `gradle/actions/setup-gradle@v6` 提供与 AGP 9.x 匹配的 Gradle 9.x（已在 PATH 上），构建命令是 `gradle :app:assembleRelease --no-daemon`，**不是** `./gradlew ...`（仓库未提交 wrapper）。
- 不要在 workflow 里现场 `gradle wrapper --gradle-version 8.13` 之类的生成命令——那会造成 AGP 9.x 配 Gradle 8.x 的版本错配。
- 「密钥有没有」的判断放在 shell step 内部：`if [ -n "$SIGNING_KEY" ]`。GitHub 的 `secrets.*` 不能出现在 step 级 `if:` 表达式里，否则整个 workflow 会被解析成 0 个 job。
- 构建后有一步 **Verify APK signature**：产物文件名含 `unsigned` 就直接让 CI 失败，并用 runner 自带的 `apksigner verify --print-certs` 打印签名证书指纹——避免把装不上的包挂到 Release 页上。
- workflow 顶层**必须**写 `permissions: contents: write`：`softprops/action-gh-release` 用 `GITHUB_TOKEN` 建 Release，而缺省权限只有 read。本仓库第一次打 tag 时就是漏了这行，Release 步骤报 403 `Resource not accessible by integration`（构建本身是绿的，很容易看漏），现已修好。
- Secrets 也可以不走网页、直接用 API 批量写入（自动化场景）：先 `GET /repos/{owner}/{repo}/actions/secrets/public-key` 拿 `key_id` 与公钥，用 NaCl sealed box（PyNaCl `public.SealedBox`）加密，再 `PUT /repos/{owner}/{repo}/actions/secrets/{NAME}`。

### 4. 触发构建

- 打 tag 推送到 GitHub：`git tag v1.0.3 && git push origin v1.0.3` → 自动构建并创建 GitHub Release 附 APK。tag 版本要与 `app/build.gradle.kts` 的 `versionName` / `versionCode` 对上——`versionCode` 不递增的话，老用户收到也升不上去；
- 或在 Actions 页面手动 `Run workflow`（手动触发不建 Release，只出 artifact）。

产物在 Actions 的 Artifacts（`app-release-apk`）中下载，文件名取决于是否配了密钥：`app-release.apk` 或 `app-release-unsigned.apk`；打 `v*` tag 时 workflow 会额外创建 GitHub Release 并附上 APK。

## 已发布版本与产物校验

| tag | versionName / versionCode | Release 资产 | 状态 |
|---|---|---|---|
| [`v1.0.4`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.4) | `1.0.4`（versionCode 由 CI 运行号自增） | `app-release.apk`（9322638 字节 ≈ 8.89 MB） | **已签名，首帧崩溃已修（见[测试与验证现状](#测试与验证现状)），可直接下载安装** |
| [`v1.0.3`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.3) | `1.0.3` / `3` | `app-release.apk` | ⚠️ **已被取代**：APK 在模拟器上首帧 SIGSEGV 崩溃（RenderNode 环，见[测试与验证现状](#测试与验证现状)）。请勿安装，直接用 `v1.0.4` |
| [`v1.0.2`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.2) | `1.0.2` / `2` | `app-release.apk`（9306061 字节 ≈ 8.87 MB） | **已签名，可直接下载安装** |
| `v1.0.1` | — | 无 APK 资产（只有 source zip/tar.gz） | 签名链路启用前的构建 |

下载：`https://github.com/guocheng1378/miuix-apk-template/releases/download/v1.0.4/app-release.apk`

`v1.0.4` 的完整性（CI 构建产物，签名走与 `v1.0.2` 相同的 keystore，故证书指纹一致）：

- 签名方案：**APK Signature Scheme v2**，RSA 2048，单签名者（自签证书）
- **APK SHA-256**：`652c1d4a62e224fe0e6ff34d081860e89c6f6cae45aeb3d2f55cd656deef24aa`
- **证书 SHA-256**：`445a46ddcad6465947735503f6d80f2b556337ff5bd6a67470f378e1092195c7`（与 v1.0.2 相同，未换密钥）

> 换自己的密钥后这两个指纹都会变，别拿本仓库的值去校验 fork 的产物。

拿到 APK 后自行核对：

```bash
# 1) 完整性：结果应等于上面的 APK SHA-256
sha256sum app-release.apk

# 2) 签名与证书指纹：Signer #1 certificate SHA-256 digest 应等于上面的证书 SHA-256
#    apksigner 在 Android SDK 的 build-tools/<版本>/ 下，本机需有 JDK + Android SDK
apksigner verify --verbose --print-certs app-release.apk
```

> GitHub 会在每个 Release 资产上直接标 `sha256:<摘要>`，可与上面第一条对照。
> 换自己的密钥后这两个指纹都会变，别拿本仓库的值去校验 fork 的产物。

## 快速使用

### 直接装 App（不写代码）

去 [v1.0.4 Release](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.4) 下载 `app-release.apk`，核对 sha256 后安装（Android 需允许「安装未知来源应用」；自签证书会提示不受信任，属预期）：

```bash
sha256sum app-release.apk
# 期望：652c1d4a62e224fe0e6ff34d081860e89c6f6cae45aeb3d2f55cd656deef24aa
```

### fork 后自己改壳发版

1. fork 本仓库 → `Settings → Secrets and variables → Actions` 配齐 4 个 Secrets（`SIGNING_KEY` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD`，生成方式见 [GitHub Actions 自动构建 + 签名](#github-actions-自动构建--签名)）。**不配的话 CI 的签名校验一步会直接判红。**
2. 改三处即可换皮：`shared/src/commonMain/kotlin/top/yukonga/miuixapptemplate/App.kt` 的页面内容、`app/build.gradle.kts` 的 `applicationId`、`app/src/main/res/values/strings.xml` 的 `app_name`。
3. 打 tag 触发全自动出包：

```bash
git tag v1.0.0 && git push origin v1.0.0
# Actions 自动编译 → 签名 → apksigner verify → 建 Release 附 APK
```

### 用 skill 生成同类 App

本仓库自带 `skills/generate-miuix-app/`，是一个符合 agentskills 规范的 AI skill：把它放进 agent 的 skills 目录，说一句「生成一个 MIUIX 风格的 APK」即可按模板脚手架产出一个新工程（含液态玻璃底栏、导航、主题、CI 配置），并自动避开 [测试与验证现状](#测试与验证现状) 里记录的那几个运行时坑。约束与接线规则见 `skills/generate-miuix-app/SKILL.md`。

## 测试与验证现状

CI 目前跑**三套**工作流，结论均基于 GitHub Actions 真实产物（非静态推断）：

1. **构建 + emulator 冒烟**（`build-apk.yml`，`push: tags: v*` / `workflow_dispatch`）：`gradle :app:assembleRelease` 编译通过后，在 CI 模拟器里 `adb install` 并启动 `MainActivity`，截一张图、抓 logcat，确认**不崩溃、进程还在**。`v1.0.4` 这轮冒烟**首次真实抓到并修复了一个首帧 native 崩溃**（见下）。
2. **JVM 截图回归**（`test.yml`，`push` / `pull_request`）：Robolectric + layoutlib 渲染预览、落 PNG。只扫 `preview.settings` 包（见下「AGSL 限制」），目前产出 `SettingsPageLight` / `SettingsPageDark` 两张图，全绿。
3. **依赖审查**（`dependency-review.yml`，PR / master）：GitHub Dependency Review Action 逐依赖比对，全绿。

### AGSL 限制（为什么截图回归不扫全部预览）

miuix 的 `miuix-squircle`（`Card` / `squircleSurface`）与 `miuix-blur`（液态底栏）的 AGSL 着色器用了 `layout(color)` 限定符，而 Robolectric 的内嵌 Skia 不认它，构造 `RuntimeShader` 即抛 `IllegalArgumentException("error: 'color' is not a valid layout qualifier")`。所以含这些路径的预览（液态底栏 / HomePage 的 Card / 整棵 App）**不能进 JVM 扫描**，放在 `preview` 包里由 emulator 冒烟 job 覆盖；只有 `SettingsPage`（纯 miuix-preference，无 AGSL）放在 `preview.settings` 包被截图回归扫描。这是 Robolectric 的能力边界，不是 app 问题。

### 已修：首帧 native 崩溃（RenderNode 环）

`v1.0.3` 的 APK 在 Android 模拟器上**首帧即 SIGSEGV 崩溃**，解栈是 512 层 `RenderNode::prepareTreeImpl` 递归。根因：`backdrop` 实例既挂在 `HomePage`/`DetailPage` 的 `Column` 上 `layerBackdrop` 注册，又被这些 `Column` 后代里的 `LiquidButton` 用 `textureBlur` 采样——**采样者是注册者的后代、且用同一实例**，hwui `drawRenderNode` 自引用成环。修复：页面内容只在 `Scaffold` content 槽统一注册一次；页面内按钮改用独立 `buttonBackdrop` 实例，注册在纯装饰背景兄弟层。`v1.0.4` 起已修复（冒烟通过）。机制与判据见 `skills/generate-miuix-app/references/pitfalls.md` G1 / G3。

### 仍未执行

- **真机逐页手感**：手势返回、下拉刷新手感、左滑删除阈值、液态玻璃在真机的实际观感，仍没有人工/自动化记录（开发环境只有 CI 模拟器，没有真机）。
- **设置页 / 详情页的大标题折叠接线**：`App.kt` 里这两页补上的 `.nestedScroll(scrollBehavior.nestedScrollConnection)`（以及详情页为保证可滚补的说明卡）**尚未经过编译与截图验证**——本仓库的开发环境没有 JDK / Android SDK / Gradle，改动只做了源码级核对（API 名与形参照着 miuix `0.9.4-rc01` sources jar 逐条确认）。下一次 CI 跑绿之前，这条算"已改未验"。
- **GitHub 报的 47 个依赖漏洞**：全部是 Gradle 插件 / Robolectric 等**构建与测试期**传递依赖（netty、bouncycastle、jose4j 等），**不进 Release APK**（已解包核对：APK 只含 okhttp / coil / miuix / compose 等运行时依赖）。升级需动 Gradle / Kotlin / AGP 版本，会冲掉整套已验证版本矩阵，暂不动。

## 限制与未验证项

- **本机没 JDK / Android SDK 就构建不了**：仓库只提交了 `gradle-wrapper.properties`，没有 `gradlew` 和 wrapper jar，本地既跑不了 `./gradlew`，也没有 `gradle` 可配 AGP 9.x。所有「构建通过」的结论都来自 GitHub Actions，不是本地实测。
- **模拟器 / 软件渲染 ≠ 真机质感**：液态玻璃依赖 Android `RuntimeShader` / `RenderEffect`（Android 12+ 且平台实现完整）。模拟器与软件渲染下模糊、折射、高光边缘的表现和真机差得很远，**看模拟器截图判断玻璃效果不可靠**；不支持的平台 `backdrop` 为 null，直接降级成纯色底栏。
- **真机冒烟未做**：逐页操作、手势返回、下拉刷新手感、左滑删除阈值都没有人工或自动化验证记录（见上一节）。
- **自签证书，系统会提示「来源不受信任」**：预期行为——没上架商店、没走 Play App Signing。首次安装需在系统里允许「安装未知应用」；换密钥重新签名会导致老包无法覆盖升级。
- **keystore 一旦丢失就无法覆盖升级**：同一 `applicationId` 必须用同一把签名密钥。`release.p12` 与口令必须异地备份，且永远不能提交进仓库（`.gitignore` 已忽略 `*.jks` / `*.p12` / `*.keystore`）；丢了只能换包名重发，或让老用户卸载重装。
- **产物未开 R8**：`isMinifyEnabled = false`，所以 `v1.0.2` 的 APK 约 8.9 MB。开混淆要自行补 Compose / MIUIX 的 keep 规则。

## 液态玻璃 + miuix-nav 导航

### 液态玻璃底栏（悬浮套壳）

`shared/src/commonMain/kotlin/component/liquid/` 与 `component/animation/`、`ui/` 来自 MIUIX 官方示例，**改编自 Kyant0/AndroidLiquidGlass（Apache-2.0）**。它把 `miuix-blur` 的 `LayerBackdrop` / `textureBlur` / `Highlight` / 设备倾斜传感器（`rememberDeviceTilt`）组合成 `IosLiquidGlassNavigationBar`。已在 `App.kt` 接线：

- `rememberLayerBackdrop()` 捕获“栏背后”内容；
- 内容区用 `.layerBackdrop(backdrop)` 标记；
- 底栏 `IosLiquidGlassNavigationBar(backdrop, isBlurActive)` 实时折射背后画面，外层再套 `textureBlur` 增强玻璃质感。

> 依赖：`miuix-blur`（已在 `shared/build.gradle.kts` 打开）。效果依赖 **Android `RuntimeShader`**（Android 12+ / 有 `RenderEffect` 的平台）；不支持时 `backdrop` 为 null，自动降级为纯色底栏。

### miuix-nav 页面栈导航

用 `miuix-nav` 替代了标准 Compose 的 `AnimatedContent`，提供：

- **页面栈**：顶层三 tab + 详情页（`Route.Detail(id)`），支持 push/pop/replace；
- **返回手势**：`NavDisplay` 自带边缘滑动返回与系统预测性返回手势（`App.kt` 里没有手写 handler）；
- **状态保存**：返回栈跨配置变更/进程重建自动保存（`@Serializable` 路由）；
- **转场动画**：miuix-nav 默认转场，详情页 push/pop 自带过渡。

#### 路由定义

`Route.kt` 定义 `@Serializable sealed interface Route : NavKey`，内含三个 `data object`（`Home` / `Image` / `Settings`）和一个带参 `data class Detail(id: Int)`。`@Serializable` 是 `rememberNavBackStack` 序列化的硬要求，闭式多态无需 `SerializersModule`。

#### 用法示意

```kotlin
val nav = rememberNavController<Route>(Route.Home)
val scrollBehavior = MiuixScrollBehavior()   // 全栈共用一个，TopAppBar 只此一个

Scaffold(
    topBar = { TopAppBar(title = topTitle, largeTitle = topLargeTitle, scrollBehavior = scrollBehavior) },
    bottomBar = { ... },
) { innerPadding ->
    Box(Modifier.fillMaxSize().padding(innerPadding)) {
        NavDisplay(navController = nav, modifier = Modifier.fillMaxSize()) {
            // 首页 / 图片页：包 PullToRefresh 并把 scrollBehavior 交给它转发
            entry<Route.Home> { HomePage(..., scrollBehavior = scrollBehavior) }
            entry<Route.Image> { ImagePage(onOpenDetail = { nav.push(Route.Detail(it)) }, scrollBehavior = scrollBehavior) }
            // 设置页 / 详情页：没有 PullToRefresh，页面自己在滚动容器上接 nestedScroll
            entry<Route.Settings> { SettingsPage(..., scrollBehavior = scrollBehavior) }
            entry<Route.Detail> { DetailPage(it.id, onBack = { nav.pop() }, ..., scrollBehavior = scrollBehavior) }
        }
    }
}
```

- 详情页 push 时 bottomBar 和 FAB 自动隐藏，全屏展示；
- 点击底部 tab 用 `nav.replace()` 切换（清空详情栈）；
- 系统返回键 / 边缘滑动返回调用 `nav.pop()`；
- `scrollBehavior` 必须一路传到每个页面，否则那一页的大标题不折叠（见[滚动接线](#滚动接线大标题折叠)）。

## UI 特性（均可在 `App.kt` 增删）

| 特性 | 实现 | 位置 |
|---|---|---|
| 大标题折叠 TopAppBar | 顶层 `MiuixScrollBehavior()` 一个实例喂给全栈，栈顶决定标题/大标题；**每页自己接线**：首页/图片页走 `PullToRefresh(topAppBarScrollBehavior = ...)`，设置页/详情页在滚动容器上写 `.nestedScroll(scrollBehavior.nestedScrollConnection)`（miuix `Scaffold` 不接管滚动，见[滚动接线](#滚动接线大标题折叠)） | `App()` / `SettingsPage()` / `DetailPage()` |
| 主题持久化 | `AppPrefs` 接口 + Android `SharedPreferences` 实现，主题/主题色/通知**重启保留** | `AppPrefs.kt` / `AndroidAppPrefs.kt` / `App()` |
| 下拉刷新 | `PullToRefresh` + `rememberPullToRefreshState`，模拟 800ms 后复位（首页 + 图片页） | `HomePage()` / `ImagePage()` |
| 左滑删除 + 撤销 | 自写 `SwipeToDeleteItem`（foundation `draggable`），左滑露出红色删除区，删除后 `Snackbar` 可撤销 | `HomePage()` / `SwipeToDeleteItem()` |
| 底部弹层 | `OverlayBottomSheet`（MIUIX 毛玻璃弹层） | `HomePage()` |
| 设置页标准化 | `miuix-preference` 的 `RadioButtonPreference`（主题/主题色单选）+ `SwitchPreference`（通知） | `SettingsPage()` |
| 图集状态机 | `LazyVerticalGrid` + Coil `SubcomposeAsyncImage`，带**加载中/失败**占位，点击进入详情页回显该图 | `ImagePage()` / `DetailPage()` |
| squircle 圆角 | `miuix-squircle` 的 `squircleSurface`，液态按钮在降级设备（无 RuntimeShader）上用连续圆角而非纯圆 | `LiquidButton()` |
| edge-to-edge | `MainActivity.enableEdgeToEdge()`，内容延伸到状态栏/导航栏之下 | `MainActivity.kt` |

> 图片页需要网络权限和 Coil 依赖，模板已配好：`AndroidManifest.xml` 加了 `INTERNET` 权限；`shared/build.gradle.kts` 的 commonMain 加了 `coil-compose`，androidMain 加了 `coil-network-okhttp`（Coil 3 的 OkHttp 网络变体只在 Android/JVM 平台有）。

### 滚动接线（大标题折叠）

`TopAppBar(largeTitle = ..., scrollBehavior = ...)` 的大标题折叠**不是自动生效的**，它只读 `ScrollBehavior.state`，而 state 要靠有人把滚动事件喂进来。miuix `0.9.4-rc01` 的事实（逐条在官方 sources jar 里核过）：

- **`Scaffold` 不接管滚动**：`basic/Scaffold.kt:79` 的形参里没有任何 `ScrollBehavior`，它只做槽位排布并给出 `innerPadding`。指望"把 `scrollBehavior` 传给 `Scaffold`"是接不上的——它没有这个参数。
- **全库只有两个组件接受 `ScrollBehavior`**：`TopAppBar`（`basic/TopAppBar.kt:111`）和 `PullToRefresh`（`basic/PullToRefresh.kt:131`，形参名 `topAppBarScrollBehavior`）。grep 整个 sources jar，`ScrollBehavior` 也只出现在这两个文件里。
- **属性名是 `nestedScrollConnection`**：`interface ScrollBehavior`（`basic/TopAppBar.kt:422-454`）的成员是 `state` / `isPinned` / `snapAnimationSpec` / `flingAnimationSpec` / `nestedScrollConnection`。源码自己的注释就写着"A [NestedScrollConnection] that should be attached to a [Modifier.nestedScroll]"（`basic/TopAppBar.kt:451`）。**没有** `nestedScroll` 这层中间对象，`scrollBehavior.nestedScroll.connection` 是编不过的。

所以模板里两条路二选一，**每个页面各选一条**——同一页两条都写属于冗余接线：Compose 的 pre-scroll 按"由内向外"分发，内层那条 connection 会先吃掉向上滚动的量，外层 `PullToRefresh` 的连接只剩残余，行为取决于分发顺序而不是你的意图。（这条分发顺序是 Compose `NestedScrollDispatcher` 的既有语义，本仓库没有实测过双接的具体表现，只作为"别这么写"的理由，不作为现象描述。）

| 页面 | 接线方式 | 位置 |
|---|---|---|
| 首页 / 图片页 | 包 `PullToRefresh(topAppBarScrollBehavior = scrollBehavior)`，它内部 `Modifier.nestedScroll(...)` 并转发给 app bar（`basic/PullToRefresh.kt:222`、`:638-706`） | `HomePage()` / `ImagePage()` |
| 设置页 / 详情页 | 无下拉刷新语义，直接在滚动容器上 `.nestedScroll(scrollBehavior.nestedScrollConnection)` | `SettingsPage()` / `DetailPage()` |

```kotlin
// 没有 PullToRefresh 的页面必须自己接这一行，否则大标题纹丝不动
Column(
    modifier = Modifier
        .fillMaxSize()
        .nestedScroll(scrollBehavior.nestedScrollConnection)   // 注意属性名，不是 .nestedScroll.connection
        .verticalScroll(rememberScrollState())
        .padding(16.dp),
) { ... }
```

> 还有一个容易误判成"接线没生效"的条件：**内容必须高过一屏**。`Scaffold` 的 `innerPadding` 用的是 app bar 当前（展开态）高度，所以可滚区域比屏幕矮一截；页面本身撑不满时就根本没有滚动可分发，折叠自然看不到。模板的详情页因此保留了一段说明卡来保证可滚。
>
> 历史 bug：`SettingsPage` / `DetailPage` 一度只声明了 `scrollBehavior` 形参、body 里从没用它，折叠静默失效——形参没被使用在 Kotlin 里不是编译错误，只能靠肉眼或 lint 抓。

## 常见问题

- **改应用名 / 包名**：改 `app/src/main/res/values/strings.xml` 的 `app_name`，以及各 `build.gradle.kts` 的 `namespace` / `applicationId` / 包目录。
- **构建报 `minCompileSdk=37`**：`miuix 0.9.4-rc01` 的 AAR 要求 compileSdk 37，`app/build.gradle.kts` 与 `shared/build.gradle.kts` 的 `compileSdk` 都要是 37（`targetSdk` 同为 37）。
- **AGP 9 的插件冲突**：`app/build.gradle.kts` 只应用 `com.android.application` + `org.jetbrains.kotlin.plugin.compose`，**不能**再应用 `org.jetbrains.kotlin.android`（AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报错）；`shared` 用 `com.android.kotlin.multiplatform.library` + `org.jetbrains.kotlin.multiplatform` + `org.jetbrains.compose` + compose / serialization 编译器插件，也不与 `com.android.library` 混用。
- **`shared` 用 KMP 新 DSL**：Android 目标配置内联在 `kotlin { android { namespace / compileSdk = 37 / minSdk = 24 / androidResources { enable = true } } }` 里，**没有**顶层 `android { }` 块，也**不再调用** `androidTarget()`；新插件默认关掉 Android 资源处理，用到资源必须显式 `androidResources { enable = true }`。
- **`gradle.properties` 只有 5 行**：`org.gradle.jvmargs`、`org.gradle.caching`、`android.useAndroidX`、`kotlin.code.style`、`android.nonTransitiveRClass`。迁移到新 DSL 后 `android.newDsl=false` 已删除，**别再加回去**。
- **开 R8 混淆**：模板默认 `isMinifyEnabled = false` 以保证首编通过。需要体积优化时，在 `app/build.gradle.kts` 将其设为 `true` 并补充 proguard 规则（Compose / MIUIX 的 keep 规则）。
- **换 MIUIX 模块**：在 `shared/build.gradle.kts` 的 `commonMain.dependencies` 增删。模板默认六个模块全开（`miuix-ui` / `miuix-icons` / `miuix-blur` / `miuix-nav` / `miuix-preference` / `miuix-squircle`），用不到可直接注释掉。
- **图片不显示**：确认真机/模拟器联网；`INTERNET` 权限和 `coil-network-okhttp` 依赖在模板里已配好，若自定义模块记得补上。
- **跑模拟器 / 真机验证**：`adb install app/build/outputs/apk/release/app-release.apk`（Release 页上的 `app-release.apk` 也可直接下载装机）。注意 `app-release-unsigned.apk` 装不上，要先 `zipalign` + `apksigner` 签名。**本仓库的开发环境没有 adb 和设备，这条路径至今没实际跑过**，装机后是否崩溃属于未验证项。
- **上架 Play Store**：改用 `gradle :app:bundleRelease` 产出 AAB 再提交（Play 要求上传已签名的 AAB）。

### 写代码时的真实坑（都编译验证过）

- **作用域成员不要顶层 import**：`androidx.compose.foundation.layout.weight`、`androidx.compose.foundation.layout.matchParentSize` 这类是作用域内成员，import 了反而编译失败，删掉 import、靠接收者作用域解析。
- **Coil 3 组件在 `coil3.compose.*`**：如 `import coil3.compose.SubcomposeAsyncImage`，不是 `androidx.compose.*`。
- **`Icon` 用 miuix 的**：`import top.yukonga.miuix.kmp.basic.Icon`，不是 `androidx.compose.foundation.Icon`。
- **`nestedScroll` 要写对属性名**：miuix 的 `ScrollBehavior` 暴露的是 `nestedScrollConnection`（`basic/TopAppBar.kt:454`），**没有** `nestedScroll` 这个中间对象——`.nestedScroll(scrollBehavior.nestedScroll.connection)` 会编译失败，正确写法是 `.nestedScroll(scrollBehavior.nestedScrollConnection)`。miuix `Scaffold` 的形参里根本没有 `ScrollBehavior`（`basic/Scaffold.kt:79`），它只排布槽位、给 `innerPadding`，**不接管滚动**，所以每页必须自己接线，见[滚动接线](#滚动接线大标题折叠)。
