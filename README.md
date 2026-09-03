# MIUIX APK 模板（Compose Multiplatform）

![Build Release APK](https://github.com/guocheng1378/miuix-apk-template/actions/workflows/build-apk.yml/badge.svg)
![Screenshot 回归](https://github.com/guocheng1378/miuix-apk-template/actions/workflows/test.yml/badge.svg)
![Dependency Review](https://github.com/guocheng1378/miuix-apk-template/actions/workflows/dependency-review.yml/badge.svg)

用 **MIUIX 组件库**（`top.yukonga.miuix.kmp`）搭原生 Android 界面、并自动产出**已签名 Release APK** 的脚手架；附带一个符合 agentskills 规范的 AI skill，能把整套结构自动套到新包名的新工程上。编译、签名、装机冒烟全在 GitHub Actions 完成，**本机不需要 JDK / Android SDK / Gradle**。

## 三条入口

| 我想做什么 | 一步到位 | 详见 |
|---|---|---|
| 装个 App 看效果 | [v1.0.5 Release](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.5) 下载 `app-release.apk`（8.89 MB，已签名） | [直接装 App](#install) |
| fork 本仓库改壳发版 | 配 4 个 Secrets + 改 18 处身份项（**不是**「改三处」） | [路径 A：手动改壳](#path-manual) |
| 让 AI 自动生成同类 App | `derive-app.sh` 一条命令派生 + `set-gh-secrets.py` 一次写齐密钥 | [路径 B：脚手架 / skill](#path-skill) |

> **开工前必须先知道的三件事**
> 1. fork 后**不配齐 4 个签名 Secrets，CI 必红**：产物是 `app-release-unsigned.apk`，而 `Verify APK signature` 一步对含 `unsigned` 的文件名直接判失败。要么配齐，要么放宽那一步。
> 2. `compileSdk` **必须是 37**：`miuix 0.9.4-rc01` 七个模块的 AAR 全部声明 `minCompileSdk=37`，AGP 直接拒绝构建，不可绕过。
> 3. 证书是**自签**的，系统会提示「来源不受信任」，属预期。keystore 一旦丢失，同一 `applicationId` 再也无法覆盖升级到已装用户机上。

## 这是什么

### App 功能（模板里真能跑起来的界面）

- **悬浮液态玻璃底栏**：`miuix-blur` 的 `LayerBackdrop` / `textureBlur` / `Highlight` + 设备倾斜传感器（`rememberDeviceTilt`）组合成 `IosLiquidGlassNavigationBar`，实时折射背后画面；组件另留了 `badge` 角标槽位（`LiquidGlassNavigationBar.kt:195`、`:372` 的 `BadgedBox`），模板没用到但可直接取用。不支持 `RuntimeShader` 的设备自动降级为不透明底栏（[降级表](#degrade)）。
- **miuix-nav 页面栈**：三个顶层 tab（首页 / 图片 / 设置）+ 带参详情页 `Route.Detail(id)`，支持 push/pop/replace；返回栈用 `@Serializable` 路由做状态保存。
- **主题四模式 + 7 个强调色**：跟随系统 / 浅色 / 深色 / **Monet 动态取色**（`App.kt:567-570`），强调色 7 档（`App.kt:572-588`，取色逻辑在 `ui/Theme.kt:57-65` 的 `KeyColors`）；偏好经 `SharedPreferences` 持久化，重启保留。
- **大标题折叠 TopAppBar**：全栈共用一个 `MiuixScrollBehavior`，四页（首页 / 图片 / 设置 / 详情）都已接线，每页自己接（唯一权威说明在 [滚动接线](#scroll-wiring)）。
- **首页**：下拉刷新、左滑删除 + Snackbar 撤销、`OverlayBottomSheet` 底部弹层、FAB、loading/empty 状态演示（`App.kt:370-397`）、Switch / Slider / `LiquidButton` 控件演示（`App.kt:353-368`）。
- **图片页**：`LazyVerticalGrid` + Coil 3 `SubcomposeAsyncImage`，带加载中/失败占位，**自己也有下拉刷新**（`App.kt:478-491`）；点击进详情页回显该图（详情页回显**无**加载中/失败占位）。
- **设置页**：`miuix-preference` 的 `RadioButtonPreference`（主题/主题色）+ `SwitchPreference`（通知）+ 三态 `CheckboxPreference` 演示（`App.kt:597-613`）。
- **底栏 / FAB 随栈顶页显隐**：push 到详情页时两者自动隐藏（`App.kt:191-199` 的 `isTopTab`）。
- **`LiquidButton` + `LiquidButtonBackdropLayer`**：独立 backdrop 实例的液态按钮，`App.kt:724-761` / `:680-715`。
- **edge-to-edge**、squircle 连续圆角降级、自定义启动图标、`allowBackup="true"`（`AndroidManifest.xml:11`）。
- **静态原型**：[preview.html](preview.html)（浏览器打开的 HTML 版式稿，不参与 Gradle 构建）。

### 工程与工具链能力

- **三套 CI 工作流**：[build-apk.yml](.github/workflows/build-apk.yml)（编译 + 签名 + 签名校验 + emulator 冒烟 + 建 Release）、[test.yml](.github/workflows/test.yml)（Robolectric JVM 截图回归）、[dependency-review.yml](.github/workflows/dependency-review.yml)（逐依赖比对）。三者的真实触发面见 [验证现状与边界](#verify)。
- **版本号自动派生**：`versionName` 由 tag 名去 `v` 前缀得出，`versionCode` 取 `VERSION_CODE` > `GITHUB_RUN_NUMBER` > 兜底 `2`（`app/build.gradle.kts:11-31`、`:47-50`），**不需要手工对齐**。
- **emulator 冒烟有实质判定**：AOT 预热后 `adb install` + `am start`，抓 logcat 崩溃**按包名/pid 归属过滤**（不冤枉 launcher 的 ANR）、`pidof` 验进程存活、截图判空白屏。
- **五个可复用脚本**（[scripts/](skills/generate-miuix-app/scripts)）：`derive-app.sh` 派生新工程、`preflight.sh` 静态自检（1064 行，本仓库实测 PASS=94 FAIL=0）、`gen-keystore.sh` 无 JDK 产 PKCS12、`set-gh-secrets.py` 用 API 一次写 4 条 Secrets、`lint-skill.py` 检查 skill 自身。
- **可搬运的液态玻璃组件**：[assets/liquid/](skills/generate-miuix-app/assets/liquid) 下 7 个 `.kt` 与 `shared/.../component/` 实测**逐字节一致**（7/7），外加两段 snippet（签名配置、workflow 镜像）。
- **AI skill + Claude Code plugin**：[skills/generate-miuix-app/SKILL.md](skills/generate-miuix-app/SKILL.md) 可整目录放进 agent 的 skills 目录；[.claude-plugin/](.claude-plugin) 让你用 `/plugin marketplace add guocheng1378/miuix-apk-template` 直接装。

## 技术栈（CI 端到端编译验证通过的组合）

| 组件 | 版本 |
|---|---|
| Kotlin | `2.4.10` |
| Compose Multiplatform | `1.12.0` |
| Android Gradle Plugin | `9.3.2` |
| MIUIX | `0.9.4-rc01`（`ui` + `icons` + `blur` + `nav` + `preference` + `squircle` 六模块同版本） |
| Coil | `3.6.1`（`coil-compose` common + `coil-network-okhttp` android） |
| kotlinx-serialization | `1.11.0` |
| compileSdk / targetSdk | `37` |
| minSdk | `24`（`miuix-blur` 需 `tools:overrideLibrary` 放行，见下） |
| JDK（CI） | `21`（Zulu） |
| Gradle | `9.7.1`（`gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl`） |

## 支持范围

### 版本与硬性前提

| 项 | 要求 | 不满足时的表现 |
|---|---|---|
| `compileSdk` | **37** | AGP 直接拒绝构建（`minCompileSdk=37`，**不可绕过**） |
| `targetSdk` | 37 | 能构建，但与 CI 验证矩阵不一致 |
| `minSdk`（构建期） | 24 | 低于 24 时 miuix 六模块均不接受 |
| 运行期完整效果 | **API 33 / Android 13+** | 低于 33 无 `RuntimeShader`，走降级 |
| 运行期可安装 | API 24+（**理论值，未实测**） | 见下方两条风险 |

关于 `minSdk` 的准确说法：`miuix-blur` 的 AAR 声明 `minSdkVersion=33`，模板整体 `minSdk=24` 能编过，是因为 [AndroidManifest.xml](app/src/main/AndroidManifest.xml) 第 8 行写了 `<uses-sdk tools:overrideLibrary="top.yukonga.miuix.kmp.blur"/>`。**fork 时删掉这行会直接构建失败。** 两者性质不同：`minCompileSdk` 是 AGP 层面的硬失败，blur 的 `minSdk 33` 可以 `overrideLibrary` 放行，但运行期必须走降级分支。

### <a id="degrade" name="degrade"></a>降级表（`isRuntimeShaderSupported() == false`）

判定阈值实测是 **API 33 / Android 13**（`miuix-shader` 的 `RuntimeShader.android.kt:18` 判 `Build.VERSION_CODES.TIRAMISU`），不是「Android 12 以下」。

| 环节 | 有 RuntimeShader | 无 RuntimeShader |
|---|---|---|
| `rememberLayerBackdrop()` | 返回实例，`blurActive = true`（`App.kt:123-128`） | 直接 `null`，`blurActive = false` |
| 底栏 `textureBlur` | 挂载折射层（`App.kt:207-220`） | 整段不挂 |
| 容器色 | `surfaceContainer.copy(alpha = 0.4f)` 半透明 | 同色变不透明（`LiquidGlassNavigationBar.kt:209`） |
| vibrancy / blur / lens / highlight | 逐层 shader | 换成 `background(containerColor, pillShape)`（`:417-448`） |
| 按压高光 | `Highlight` 层 | 不挂载（`:449-455`） |
| 选中滑块 | lens + innerShadow | `clip` + `background(accentColor.copy(0.15f))`（`:499`、`:547-577`） |
| `LiquidButton` | `clip(CircleShape)` + 折射 | `squircleSurface(primary.copy(0.12f), 28.dp)`（`App.kt:730-755`） |
| 透镜折射 | AGSL 采样 | 整段 no-op（`Lens.kt:29`） |
| 交互光斑 | 实时 shader | `Brush.radialGradient` 近似（`InteractiveHighlight.kt:40-41`、`:57-78`） |

降级只做到「不崩、视觉退化」。**没有**给用户显示「本设备不支持模糊」之类的提示——那是 [references](skills/generate-miuix-app/references) 对生成物的要求，模板自身未实现。

两条**未实测风险**，写在这里而不是藏在限制里：

- CI 冒烟固定跑 `api-level: 34`（`build-apk.yml:389`）。**API 24–32 的降级路径从未在任何模拟器上验过能装能跑**，上表是逐条读代码得出的结论，属「理论可行」而非「已验证支持」。
- 启动图标只有 `mipmap-anydpi-v26/` + `drawable/ic_launcher_foreground.xml`，**没有任何密度位图兜底**，API 24–25 的桌面可能取不到图标。

### 许可与第三方出处

根 [LICENSE](LICENSE) 是 Apache-2.0（`Copyright 2026 guocheng1378`）；skill 侧许可声明在 [.claude-plugin/plugin.json](.claude-plugin/plugin.json)。**本仓库没有 NOTICE 文件**，不需要去找——派生时保留的是各文件第 1-6 行的出处头（`component/liquid/` 等 7 个文件改编自 Kyant0/AndroidLiquidGlass，Apache-2.0，头里同时标了 compose-miuix-ui contributors 与 SPDX），约束见 [assets/liquid/README.md](skills/generate-miuix-app/assets/liquid/README.md)。

### 明确不支持

- **AAB / 上架商店**：CI 只有 `assembleRelease`，全仓没有 `bundleRelease`。要上 Play 得自行加任务并接 Play App Signing。
- **R8 混淆**：`app/build.gradle.kts:86` 是 `isMinifyEnabled = false`，且仓库**没有** `proguard-rules.pro`。代价是 APK ≈ 8.9 MB。
- **iOS / 桌面 / web**：`settings.gradle.kts:20` 只 include `app` + `shared`，`shared/src/` 下**只有 `commonMain`** 一个源集。`LiquidGlassNavigationBar.kt:329-331` 里的 `Platform.IOS -> 20.dp` 是上游遗留死分支，不能当 iOS 支持依据。
- **多语言**：`res/` 下只有 `values/`，UI 文案全部硬编码中文。
- **本地构建**：仓库未提交 `gradlew` 与 wrapper jar（见 [限制](#verify)）。
- **像素级截图回归**：`test.yml:57` 只做 `--record`，仓库里**没有任何 golden 基线**，目前只能人工看图。
- **玻璃路径的自动化覆盖**：`shared/build.gradle.kts:117` 的截图扫描只包含 `preview.settings` 两张预览，液态玻璃完全靠 emulator 冒烟兜底。
- **无障碍：部分支持**。已有的是底栏 `semantics { selected / role = Role.Tab / onClick }`（`LiquidGlassNavigationBar.kt:342-361`）、`onKeyEvent`、`focusable()`、图标 `contentDescription = null` 防 TalkBack 双读（`:376-378`）、`clearAndSemantics`（`:471`、`:564`），以及 `App.kt` 里「返回」(`:184`) / 「图集 #$i」(`:514`) 两处描述。**没有** fontScale / 高对比 / 减少动画的适配，TalkBack 未做实测。

## 用法

### <a id="install" name="install"></a>直接装 App（不写代码）

去 [v1.0.5 Release](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.5) 下载 `app-release.apk`，核对哈希后安装（需允许「安装未知来源应用」；自签证书提示不受信任属预期）：

```bash
sha256sum app-release.apk
# 期望：3c513253a680da9cc4c85bc09b2fef1fa4f727cafe7e594b3c2ba4b8c6c1574e
```

### <a id="path-skill" name="path-skill"></a>路径 B：脚手架 / skill 自动生成（推荐）

**整条链路实测跑通过**：派生新包名 → preflight 全绿 → 产密钥 → 写 Secrets → 推仓 → 打 tag → CI 出已签名 APK。

```bash
# 1) 从模板派生新工程（--out 目录必须不存在；末尾会自动跑一次 preflight）
bash skills/generate-miuix-app/scripts/derive-app.sh \
  --package io.example.myapp --name "My App" --out ../myapp

# 2) 无 JDK 产 PKCS12 签名密钥（产物含 release.p12 / password.txt / alias.txt，并打印单行 base64）
bash skills/generate-miuix-app/scripts/gen-keystore.sh --outdir ./ks --alias release

# 3) 一次写齐 4 条 Secrets（需要 pynacl：python3 -m venv .venv && .venv/bin/pip install pynacl）
export GH_TOKEN=<你的 PAT>
python3 skills/generate-miuix-app/scripts/set-gh-secrets.py --repo owner/myapp --from-dir ./ks

# 4) 推上去并打 tag（tag 号自己定，versionCode 由 CI 自动派生）
cd ../myapp && git add -A && git commit -m "init" && git push -u origin master
git tag v0.1.0 && git push origin v0.1.0
```

给 agent 用时，把 `skills/generate-miuix-app/` 整目录放进它的 skills 目录，说一句「生成一个 MIUIX 风格的 APK」即可；或作为 Claude Code 插件安装：`/plugin marketplace add guocheng1378/miuix-apk-template`。约束与接线规则写在 [SKILL.md](skills/generate-miuix-app/SKILL.md)，踩坑清单在 [references/pitfalls.md](skills/generate-miuix-app/references/pitfalls.md)。

脚本真实签名（照抄可用）：

| 脚本 | 参数 | 失败表现 |
|---|---|---|
| `derive-app.sh` | `--package --name --out` 必填，`[--prefs-key] [--template]` | 包名不匹配 `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$` 退出码 1；`--out` 已存在即拒绝 |
| `gen-keystore.sh` | `--alias --subject --days --outdir --password` | 默认 alias **`release`**、days 10950、outdir `./keystore`；口令留空则 `openssl rand -hex 16`；产物 `chmod 600` 并回读自检 |
| `set-gh-secrets.py` | `--repo`（必填）`--token-env`（默认 `GH_TOKEN`）`--from-dir` `--set K=V` | 缺 pynacl 报错并建议 venv；`--from-dir` 缺 `alias.txt` 时回落 `"release"` |
| `preflight.sh` | **位置参数** `$1` = 仓库根，默认 `.` | 目录不存在退出码 2；任一 FAIL 退出码 1；WARN 不影响退出码 |
| `lint-skill.py` | `argv[1]` = **skill 目录**（含 `SKILL.md`） | 对仓库根跑会报 `FATAL 缺 SKILL.md` |

### <a id="path-manual" name="path-manual"></a>路径 A：fork 后手动改壳

1. fork 本仓库 → `Settings → Secrets and variables → Actions` 配齐 4 个 Secrets（[生成方式](#build-sign)）。**不配则 CI 判红。**
2. 换皮要改的身份项**实测是 18 处**（若保留 `skills/` 目录则 **19 处**），不是「改三处」：

| 类别 | 处数 | 位置 |
|---|---|---|
| 目录路径（需 `git mv`） | 2 | `app/src/main/kotlin/top/yukonga/miuixapptemplate/`、`shared/src/commonMain/kotlin/top/yukonga/miuixapptemplate/` |
| `package` 声明 | 5 | `MainActivity.kt`、`AndroidAppPrefs.kt`、`App.kt`、`AppPrefs.kt`、`Route.kt` |
| `namespace` | 2 | `app/build.gradle.kts:39`、`shared/build.gradle.kts:23`（**后者带 `.shared` 后缀**，不是同一个值） |
| 跨模块 `import` | 4 | `shared/.../preview/Previews.kt:13-15`（3 条）、`preview/settings/SettingsPreviews.kt:6` |
| `applicationId` | 1 | `app/build.gradle.kts` |
| workflow 的 `APP_ID` **定义** | 1 | `build-apk.yml:103`（该文件里 `APP_ID` 出现 8 次，另外 7 次都是 `$APP_ID` 引用，只需改定义这一行） |
| 小计（纯文本替换） | **15** | |
| 应用名字符串 | 1 | `strings.xml:2` 的 `<string name="app_name">MIUIX 模板</string>`——桌面标签与顶栏标题都取这一个值 |
| 工程名 | 1 | `settings.gradle.kts:18` 的 `rootProject.name` |
| 偏好存储 key | 1 | `AndroidAppPrefs.kt:12` 的 `getSharedPreferences("miuix_template_prefs")`（不改会和同设备其它 fork 抢存储） |
| 小计（隐性身份项，grep 包名抓不到） | **18** | |
| skill 的 workflow 镜像 | 1 | `assets/workflow-build-apk.yml:118`（**只有保留 `skills/` 时才需要**）→ **19** |

3. 改完**必须**跑一次自检，退出码 0 才算干净：

```bash
bash skills/generate-miuix-app/scripts/preflight.sh .
```

4. 打 tag 触发全自动出包（`git tag vX.Y.Z && git push origin vX.Y.Z`）。

> 强烈建议走路径 B。上面这串清单正是 `derive-app.sh` 存在的理由——它一次改完并自带 preflight。

<a id="build-sign" name="build-sign"></a>
## 构建与签名

### 1. 生成签名密钥（只需一次）

**推荐：openssl 直接产 PKCS12，不需要装 JDK**（本仓库 release 密钥就是这么产出来的）：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 10950 -nodes \
  -keyout key.pem -out cert.pem -subj "/C=CN/O=myorg/CN=my-release"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out release.p12 \
  -name release -passout pass:'<你的口令>'
base64 -w0 release.p12          # 这一整行输出作为 SIGNING_KEY 的值
```

用 PKCS12 时 `app/build.gradle.kts` 必须显式声明 `storeType = "PKCS12"`，否则 AGP 按默认 JKS 读取会失败（模板已设好）。

**备选：本机有 JDK 时用 keytool**（产出 JKS，此时把 `storeType` 去掉或改成 `"JKS"`）：

```bash
keytool -genkeypair -v -keystore release.keystore -keyalg RSA -keysize 2048 -validity 10000 -alias release
base64 -w0 release.keystore
```

> ⚠️ keystore 与口令**必须异地备份**，且绝不能提交进仓库（`.gitignore` 已忽略 `*.jks` / `*.p12` / `*.keystore`）。丢了它，这个 `applicationId` 就再也无法以覆盖升级的方式装到已装用户机上。

### 2. 在仓库配置 Secrets

| Secret | 内容 |
|---|---|
| `SIGNING_KEY` | 上面 `base64 -w0` 的输出（单行 base64 的 PKCS12 内容） |
| `KEYSTORE_PASSWORD` | keystore 密码 |
| `KEY_ALIAS` | 上面的 alias（`gen-keystore.sh` 默认是 `release`，不是 `mykey`） |
| `KEY_PASSWORD` | 密钥密码 |

> 四个名字都要对上：workflow 把 `SIGNING_KEY` 解成 `keystore.p12`，再以 `KEYSTORE_PASS` / `KEY_ALIAS` / `KEY_PASSWORD` 三个环境变量传给 Gradle（`app/build.gradle.kts` 的 `signingProp()` 先读环境变量、再读 `local.properties`）。`KEYSTORE_PATH` 不是 Secret，只用于本地。
>
> 缺任何一个密钥时 AGP 干脆不配 signingConfig，产物是 **`app-release-unsigned.apk`**——**不会**回退成 debug 签名的可安装包。这种包若真要安装/上架，需自行 `zipalign` + `apksigner sign`。

### 3. 构建命令与真实形态

- CI 用 `gradle/actions/setup-gradle@v6` 提供与 AGP 9.x 匹配的 Gradle 9.x（已在 PATH 上），构建命令是 `gradle :app:assembleRelease --no-daemon`，**不是** `./gradlew ...`（仓库未提交 wrapper）。
- 不要在 workflow 里现场 `gradle wrapper --gradle-version 8.13` 之类——那会造成 AGP 9.x 配 Gradle 8.x 的版本错配。
- 「密钥有没有」的判断放在 shell step 内部：`if [ -n "$SIGNING_KEY" ]`。GitHub 的 `secrets.*` **不能出现在 step 级 `if:` 表达式里**，否则整个 workflow 会被解析成 0 个 job。
- 构建后有一步 **Verify APK signature**：文件名含 `unsigned` 直接让 CI 失败，并用 runner 自带的 `apksigner verify --print-certs` 打印证书指纹——避免把装不上的包挂到 Release 页上。
- workflow 顶层**必须**写 `permissions: contents: write`：`softprops/action-gh-release` 用 `GITHUB_TOKEN` 建 Release，缺省权限只有 read。本仓库第一次打 tag 就是漏了这行，Release 步骤报 403 `Resource not accessible by integration`（构建本身是绿的，很容易看漏），现已修好。
- Secrets 也可以不走网页、直接用 API 批量写入：先 `GET /repos/{owner}/{repo}/actions/secrets/public-key` 拿 `key_id` 与公钥，用 NaCl sealed box（PyNaCl `public.SealedBox`）加密，再 `PUT .../actions/secrets/{NAME}`。`set-gh-secrets.py` 就是把这套封装好了。

### 4. 触发构建

- **打 tag**：`git tag vX.Y.Z && git push origin vX.Y.Z` → 自动构建、签名、校验、建 GitHub Release 附 APK。`versionName` 直接取 tag 名去 `v` 前缀，`versionCode` 取 `GITHUB_RUN_NUMBER`（可用环境变量 `VERSION_CODE` 覆盖），**不需要手工对齐**。
- **手动 `Run workflow`**：同样出 artifact，但**不建 Release**（`build-apk.yml:77` 的 `if: startsWith(github.ref,'refs/tags/')` 决定只有 tag 触发才建）。

产物在 Actions 的 Artifacts（`app-release-apk`）中下载，文件名取决于是否配了密钥：`app-release.apk` 或 `app-release-unsigned.apk`。

<a id="versions" name="versions"></a>
## 已发布版本与产物校验

| tag | versionName / versionCode | Release 资产 | 状态 |
|---|---|---|---|
| [`v1.0.5`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.5) | `1.0.5` / `14` | `app-release.apk`（9322638 字节 ≈ 8.89 MB） | **已签名，当前推荐版本**：设置页 / 详情页补上大标题折叠接线（[滚动接线](#scroll-wiring)）。⚠ 它出自 **run#14（该 run 整体是红的）**，原因见 [已知问题](#known-issues) 的「环境性假红」 |
| [`v1.0.4`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.4) | `1.0.4` / `12` | `app-release.apk`（9322638 字节 ≈ 8.89 MB） | **已签名，首帧崩溃已修，可直接下载安装** |
| [`v1.0.3`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.3) | `1.0.3` / **`10`** | `app-release.apk` | ⚠️ **已被取代**：APK 在模拟器上首帧 SIGSEGV 崩溃（RenderNode 自引用成环）。**请勿安装**，直接用 `v1.0.5` |
| [`v1.0.2`](https://github.com/guocheng1378/miuix-apk-template/releases/tag/v1.0.2) | `1.0.2` / `2` | `app-release.apk`（9306061 字节 ≈ 8.87 MB） | **已签名，可直接下载安装** |
| `v1.0.1` | — | **没有 Release 对象**（`GET /releases/tags/v1.0.1` 返回 404，只有 git tag `5e9efab`） | 签名链路启用前的构建 |

> 上表的 `versionCode` 不连续（14 / 12 / 10 / 2）是**正常的**：它们取自各自构建的 `GITHUB_RUN_NUMBER`，不是手工递增的序号。

`v1.0.5` 的完整性（签名走与 `v1.0.2` / `v1.0.4` 相同的 keystore，故证书指纹一致）：

- 签名方案：APK Signing Block 内实测含 **v2（`0x7109871a`）+ v3（`0x504b4453`）+ v3.1（`0x42726577`）** 三个 block；证书为自签 RSA 2048。（签名者数量未做严格解析验证，此处不宣称。）
- **APK SHA-256**：`3c513253a680da9cc4c85bc09b2fef1fa4f727cafe7e594b3c2ba4b8c6c1574e`
- **证书 SHA-256**：`445a46ddcad6465947735503f6d80f2b556337ff5bd6a67470f378e1092195c7`（与 v1.0.2 / v1.0.4 相同，未换密钥）

> `v1.0.3` / `v1.0.4` / `v1.0.5` 三个版本 APK 字节数**同为 9322638**，纯属 zip 对齐巧合。`v1.0.4` 的 SHA-256 是 `652c1d4a62e224fe0e6ff34d081860e89c6f6cae45aeb3d2f55cd656deef24aa`，与 `v1.0.5` 不同，确认是独立构建。
>
> 换自己的密钥后这两个指纹都会变，别拿本仓库的值去校验 fork 的产物。

```bash
sha256sum app-release.apk                                # 应等于上面的 APK SHA-256
apksigner verify --verbose --print-certs app-release.apk # 证书摘要应等于上面的证书 SHA-256
```

`apksigner` 在 Android SDK 的 `build-tools/<版本>/` 下，本机需有 JDK + Android SDK。GitHub 也会在每个 Release 资产上直接标 `sha256:<摘要>`，可与第一条对照。

> **两个 CI 修复不在任何 tag 里**：`40835bd`（冒烟崩溃断言按归属过滤）与 `987724d`（AOT 预热 + 空白屏判定）都晚于 `v1.0.5` 的提交点，`git tag --contains` 实测为空。对 App 使用者无影响（纯 CI 侧改动），但**fork 本仓库用 CI 的人会拿到旧版冒烟脚本**——直到下一个 tag 发布。

<a id="verify" name="verify"></a>
## 验证现状与边界

结论均来自 GitHub Actions 真实产物，不是静态推断。

**三套工作流的真实触发面**（避免「三套全绿」被误读）：

| workflow | 触发 |
|---|---|
| `build-apk.yml` | **仅** `v*` tag 或手动 `workflow_dispatch`；普通 push 不跑 |
| `test.yml` | PR + master push |
| `dependency-review.yml` | PR + master push；`fail-on-severity: moderate` |

- **最近一次三套全绿的 commit 是 `12b23fa`**（build#16 + test#11 + dep#11）。当前 HEAD `987724d` 只有 test#12 与 dep#12 绿，**build-apk 在 HEAD 上从未跑过**——因为它只认 tag，而 HEAD 之后没有新 tag。
- **emulator 冒烟**：`adb install` + `am start MainActivity` + AOT 预热，抓 logcat 崩溃按**包名/pid 归属**过滤（本行包名 / 下一行 `Process: <pkg>` / tag 括号里的 pid 属于 `pidof` 结果），再验进程存活与截图非空白。`v1.0.4` 那轮首次真实抓到并修好了一个首帧 native 崩溃。残留盲区：native crash 的 `Fatal signal` 行既不带包名、pid 也随进程消失，按归属过滤会漏判——但那种情况 `pidof` 必然为空，「进程存活」检查会 FAIL，不会放走真闪退。
- **JVM 截图回归**：Robolectric + layoutlib 渲染 `preview.settings` 包，产出 `SettingsPageLight` / `SettingsPageDark` 两张图。**只 record，不做 diff**（仓库无 golden 基线）。
- **依赖审查**：GitHub Dependency Review Action 逐依赖比对。**只在 PR 上有比对对象**；fork PR 的 graph 提交会 403 跳过；**private 仓库未开 Advanced Security 时必红**。

### AGSL 限制（为什么截图回归不扫全部预览）

`miuix-squircle`（`Card` / `squircleSurface`）与 `miuix-blur`（液态底栏）的 AGSL 着色器用了 `layout(color)` 限定符，而 Robolectric 内嵌的 Skia 不认它，构造 `RuntimeShader` 即抛 `IllegalArgumentException("error: 'color' is not a valid layout qualifier")`。所以含这些路径的预览（液态底栏 / HomePage 的 Card / 整棵 App）**不能进 JVM 扫描**，只能由 emulator 冒烟覆盖；只有纯 `miuix-preference`、无 AGSL 的 `SettingsPage` 放在 `preview.settings` 包被截图回归扫到。这是 Robolectric 的能力边界，不是 app 问题。

### 仍未执行

- **本地构建 / 本地 adb / 真机**：本仓库的开发环境**没有** JDK、Android SDK、adb 和设备，`gradle :app:assembleRelease` 与 `adb install` 这两条**本地**路径至今没实际跑过。所有「构建通过」「装机不崩」的结论都来自 **CI 模拟器**（那里 adb 和模拟器是有的，run#13–#16 反复 `adb install` + 启动 + 截图）。真机逐页手感——手势返回、下拉刷新手感、左滑删除阈值、玻璃实际观感——仍无任何人工或自动化记录。
- **模拟器 / 软件渲染 ≠ 真机质感**：看模拟器截图判断玻璃效果不可靠。
- **大标题折叠「到底折不折」仍未验**：设置页/详情页新加的 `.nestedScroll(...)` 已过 CI 编译验证，设置页也被两张截图真实渲染过——但那两张预览传的是**临时的** `MiuixScrollBehavior()`、没有配对的 `TopAppBar`，只证明「修饰符链不炸」，**不证明滚动时大标题真的折叠**。详情页没有任何预览覆盖。
  - 已确认「代码进了包」：`v1.0.5` 的 APK 解包后 dex 里能查到这两处新增的用户可见文案。
  - **最明确的遗留风险**：冒烟只 `am start` 首页，从不点进设置页/详情页，所以新接线的**渲染路径至今没有任何自动化覆盖**——它只要会在滚动时炸，当前 CI 发现不了。

<a id="known-issues" name="known-issues"></a>
## 已知问题

分四类，别把环境抖动当缺陷、也别把设计边界当 bug。

### 已修复

| 问题 | 修复 |
|---|---|
| `v1.0.3` APK 首帧 SIGSEGV（512 层 `RenderNode::prepareTreeImpl` 递归） | `v1.0.4`。根因：`backdrop` 既被页面 `Column` 用 `layerBackdrop` 注册，又被其后代 `LiquidButton` 用 `textureBlur` 采样同一实例，hwui `drawRenderNode` 自引用成环。修法：内容只在 `Scaffold` content 槽注册一次，按钮改用独立 `buttonBackdrop`。机制与判据见 [pitfalls G1](skills/generate-miuix-app/references/pitfalls.md) |
| 冒烟把 launcher 的 ANR 算成本包崩溃 | `40835bd`，改为按包名/pid/下一行 `Process:` 三条件归属过滤 |
| 建 Release 报 403 | `f2d4377`，补 `permissions: contents: write` |
| 冷 AVD 首启慢导致误判 | `987724d`，加 AOT 预热 + 空白屏判定 |

⚠ 后三条里的 `40835bd`、`987724d` **不在任何 tag 内**（见 [版本表](#versions) 末尾的说明）。

### 未修复的 app 缺陷

- **详情页 / 设置页新接线零自动化渲染覆盖**：冒烟从不点进子页（[仍未执行](#verify)）。
- **截图回归无基线**：只 `--record`，不做 diff，回归靠人眼。
- **构建/测试期依赖漏洞未处理**：GitHub 的 Dependabot 面板报过 47 条（1 critical / 19 high / 25 moderate / 2 low），全部是 Gradle 插件 / Robolectric 等**构建与测试期**传递依赖（netty、bouncycastle、jose4j 等），**不进 Release APK**（已解包核对：APK 只含 okhttp / coil / miuix / compose 等运行时依赖）。升级要动 Gradle / Kotlin / AGP 版本，会冲掉整套已验证矩阵，暂不动。⚠ 该数字**匿名核不到**（`GET /dependabot/alerts` 对未授权请求返回 401），以仓库 Security 面板为准。

### 环境性假红（不是代码缺陷）

- **冷 AVD 首启 dexopt → 输入分发超时 ANR**：`v1.0.5` 的 run#14 就是这么红的。对照数据：`TotalTime 7653` vs 热态 `4705`，logcat 里 `dex2oatWallTimeMillis=7387`。app 本身安装成功、冷启 3.6s、进程存活、activity 是 `topResumed`；那条 launcher ANR 的时间戳还早于本次启动。**同一 commit 手动重跑的 run#13 是绿的**——但 dispatch 不建 Release，所以绿的那次没有产出 Release 资产。判红原因见 `build-apk.yml:87` 的注释（Release 步骤在 build job 内、smoke 靠 `needs: build` 排在它之后，所以 Release 已经建出来了 job 才红）。
- **private 仓库的 Dependency Review 必红**：需要 Advanced Security 授权。
- **截图非空但全黑**：24472 bytes 单色 `000000` vs 355230 bytes 真内容——只判「非空」不够。

### 能力边界（设计如此，不是 bug）

- Robolectric 不认 `layout(color)` AGSL；软件光栅截图不能做像素 diff。
- **miuix 版本整体不可回退**：准确说法是被 `miuix-nav` 锁死——Maven metadata 实测 `miuix-nav` 只有 `0.9.4-rc01` 一个版本，而 `ui`/`blur`/`preference`/`core` 各有 0.9.0~0.9.4-rc01 五个、`squircle` 3 个、`icons` 21 个。模板六模块同版本锁定 + nav 无第二个版本 ⇒ 没有降级空间。
- 静态检查（`preflight.sh`）抓不到 RenderNode 环和滚动接线这类问题，它只做 grep 级自检。
- 把 `secrets.*` 写进 step 级 `if:` 会让 Actions 显示 0 个 job。

## 深度参考

### <a id="scroll-wiring" name="scroll-wiring"></a>滚动接线（大标题折叠）— 本节是唯一权威出处

`TopAppBar(largeTitle = ..., scrollBehavior = ...)` 的大标题折叠**不是自动生效的**，它只读 `ScrollBehavior.state`，而 state 要靠有人把滚动事件喂进来。miuix `0.9.4-rc01` 的事实（逐条在官方 sources jar 里核过）：

- **`Scaffold` 不接管滚动**：`basic/Scaffold.kt:79` 的形参里没有任何 `ScrollBehavior`，它只做槽位排布并给出 `innerPadding`。指望「把 `scrollBehavior` 传给 `Scaffold`」是接不上的——它没有这个参数。
- **全库只有两个组件接受 `ScrollBehavior`**：`TopAppBar`（`basic/TopAppBar.kt:111`）和 `PullToRefresh`（`basic/PullToRefresh.kt:131`，形参名 `topAppBarScrollBehavior`）。grep 整个 sources jar，`ScrollBehavior` 也只出现在这两个文件里。
- **属性名是 `nestedScrollConnection`**：`interface ScrollBehavior`（`basic/TopAppBar.kt:422-454`）的成员是 `state` / `isPinned` / `snapAnimationSpec` / `flingAnimationSpec` / `nestedScrollConnection`。源码注释自己写着「A [NestedScrollConnection] that should be attached to a [Modifier.nestedScroll]」（`basic/TopAppBar.kt:451`）。**没有** `nestedScroll` 这层中间对象，`scrollBehavior.nestedScroll.connection` 编译不过。

每个页面二选一，**同一页两条都写属于冗余接线**：Compose 的 pre-scroll 按「由内向外」分发，内层 connection 会先吃掉向上滚动的量，外层 `PullToRefresh` 的连接只剩残余，行为取决于分发顺序而不是你的意图。（这条分发顺序是 Compose `NestedScrollDispatcher` 的既有语义，本仓库没有实测过双接的具体表现，只作为「别这么写」的理由，不作为现象描述。）

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

两个容易误判成「接线没生效」的条件：

- **内容必须高过一屏**。`Scaffold` 的 `innerPadding` 用的是 app bar 当前（展开态）高度，所以可滚区域比屏幕矮一截；页面本身撑不满时就根本没有滚动可分发。模板的详情页因此保留了一段说明卡来保证可滚。
- **形参没被使用在 Kotlin 里不是编译错误**。历史 bug：`SettingsPage` / `DetailPage` 一度只声明了 `scrollBehavior` 形参、body 里从没用它，折叠静默失效，只能靠肉眼或 lint 抓。

### 液态玻璃底栏（悬浮套壳）

`shared/src/commonMain/kotlin/component/liquid/` 与 `component/animation/`、`ui/` 来自 MIUIX 官方示例，**改编自 Kyant0/AndroidLiquidGlass（Apache-2.0）**。它把 `miuix-blur` 的 `LayerBackdrop` / `textureBlur` / `Highlight` / 设备倾斜传感器组合成 `IosLiquidGlassNavigationBar`。已在 `App.kt` 接线的三步：

- `rememberLayerBackdrop()` 捕获「栏背后」的内容；
- 内容区用 `.layerBackdrop(backdrop)` 标记为可被采样；
- 底栏 `IosLiquidGlassNavigationBar(backdrop, isBlurActive)` 实时折射背后画面，外层再套 `textureBlur` 增强质感。

依赖 `miuix-blur`（已在 `shared/build.gradle.kts` 打开）。效果依赖 Android `RuntimeShader`，不支持时 `backdrop` 为 null 并走 [降级表](#degrade)。**注册者 / 采样者不能是祖先后代关系且共用同一实例**，否则成环崩溃（[已知问题](#known-issues) 的 G1）。

### miuix-nav 页面栈

用 `miuix-nav` 替代标准 Compose 的 `AnimatedContent`：

- **页面栈**：顶层三 tab + 详情页 `Route.Detail(id)`，支持 push/pop/replace；
- **状态保存**：`@Serializable` 路由让返回栈可跨进程重建保存。注意 `AndroidManifest.xml:21` 的 `configChanges` 已吃掉 `orientation|screenSize|density|uiMode`，**旋转根本不重建 Activity**，这条能力的实际触发面比听起来窄；
- **转场动画**：`NavDisplay` 默认转场，详情页 push/pop 自带过渡。

> 「边缘滑动返回 / 系统预测性返回手势」是 `NavDisplay` 的库行为，本仓库代码里没有任何手写 handler（全仓 grep `enableOnBackInvokedCallback`、`predictive` 零命中），因此**不在本仓库的验证范围内**，不在此宣称。

`Route.kt` 定义 `@Serializable sealed interface Route : NavKey`，内含三个 `data object`（`Home` / `Image` / `Settings`）和一个带参 `data class Detail(id: Int)`。`@Serializable` 是 `rememberNavBackStack` 序列化的硬要求，闭式多态无需 `SerializersModule`。

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
- `scrollBehavior` 必须一路传到每个页面，否则那一页的大标题不折叠（[滚动接线](#scroll-wiring)）。

## 常见问题（构建报错类）

- **构建报 `minCompileSdk=37`**：`app/build.gradle.kts` 与 `shared/build.gradle.kts` 的 `compileSdk` 都要是 37（`targetSdk` 同为 37）。
- **AGP 9 的插件冲突**：`app/build.gradle.kts` 只应用 `com.android.application` + `org.jetbrains.kotlin.plugin.compose`，**不能**再应用 `org.jetbrains.kotlin.android`（AGP 9 已内置 Kotlin 支持，同时应用会在配置阶段报错）；`shared` 用 `com.android.kotlin.multiplatform.library` + `org.jetbrains.kotlin.multiplatform` + `org.jetbrains.compose` + compose / serialization 编译器插件，也不与 `com.android.library` 混用。
- **`shared` 用 KMP 新 DSL**：Android 目标配置内联在 `kotlin { android { namespace / compileSdk = 37 / minSdk = 24 / androidResources { enable = true } } }` 里，**没有**顶层 `android { }` 块，也**不再调用** `androidTarget()`；新插件默认关掉 Android 资源处理，用到资源必须显式 `androidResources { enable = true }`。
- **`gradle.properties` 只有 5 行**：`org.gradle.jvmargs`、`org.gradle.caching`、`android.useAndroidX`、`kotlin.code.style`、`android.nonTransitiveRClass`。迁移到新 DSL 后 `android.newDsl=false` 已删除，**别再加回去**。
- **构建报 blur 的 `minSdkVersion 33` 冲突**：`AndroidManifest.xml` 的 `<uses-sdk tools:overrideLibrary="top.yukonga.miuix.kmp.blur"/>` 被删了，补回来。
- **图片不显示**：确认真机/模拟器联网；`INTERNET` 权限和 `coil-network-okhttp` 依赖在模板里已配好，若自定义模块记得补上。
- **开 R8 混淆**：模板默认 `isMinifyEnabled = false` 以保证首编通过。需要体积优化时设为 `true` 并自行补 Compose / MIUIX 的 keep 规则（仓库里没有现成的 `proguard-rules.pro`）。
- **换 MIUIX 模块**：在 `shared/build.gradle.kts` 的 `commonMain.dependencies` 增删。模板默认六个模块全开，用不到可直接注释掉——但**别改版本号**（[能力边界](#known-issues)）。
- **写 Kotlin 时的三个 import 坑**（都编译验证过）：`weight` / `matchParentSize` 是作用域成员，顶层 import 反而编译失败；Coil 3 组件在 `coil3.compose.*` 不是 `androidx.compose.*`；`Icon` 用 `top.yukonga.miuix.kmp.basic.Icon`。更多见 [references/pitfalls.md](skills/generate-miuix-app/references/pitfalls.md)。

## 附录：工程结构

```
miuix-apk-template/
├── settings.gradle.kts             # 无根 build.gradle.kts，插件/依赖版本写在各模块 build 脚本里
├── gradle.properties               # 5 行，见 FAQ
├── gradle/wrapper/gradle-wrapper.properties   # 只提交 properties；gradlew 与 wrapper jar 未入库
├── LICENSE                         # Apache-2.0（无 NOTICE 文件）
├── preview.html                    # 浏览器里的 HTML 版式稿，不参与构建
├── .claude-plugin/plugin.json      # Claude Code 插件清单（name: generate-miuix-app）
├── shared/                         # KMP 库：只有 commonMain 一个源集
│   ├── build.gradle.kts
│   └── src/commonMain/kotlin/
│       ├── top/yukonga/miuixapptemplate/
│       │   ├── App.kt              # 页面 + 导航 + 主题（本仓库最大的一个文件）
│       │   ├── AppPrefs.kt         # 偏好持久化接口（common）
│       │   └── Route.kt            # @Serializable 路由定义
│       ├── component/liquid/       # 液态玻璃底栏（改编自 Kyant0/AndroidLiquidGlass）
│       ├── component/animation/    # 按压形变 / 高光动效
│       ├── preview/settings/       # 供 JVM 截图回归扫的预览（无 AGSL）
│       └── ui/Theme.kt             # 主题色 / KeyColors
├── app/                            # 纯 Android 应用模块
│   ├── build.gradle.kts            # applicationId / signingConfig / 版本号派生
│   └── src/main/
│       ├── AndroidManifest.xml     # 第 8 行 tools:overrideLibrary，删不掉
│       ├── kotlin/top/yukonga/miuixapptemplate/
│       │   ├── MainActivity.kt
│       │   └── AndroidAppPrefs.kt  # AppPrefs 的 SharedPreferences 实现
│       └── res/...                 # 图标、主题、字符串（只有 values/，无多语言）
├── skills/generate-miuix-app/      # 自动生成同类 App 的 skill
│   ├── SKILL.md
│   ├── references/                 # 6 篇：stack-and-build / miuix-api / pitfalls / signing-and-secrets / ci-workflow / verification
│   ├── scripts/                    # 5 个：derive-app / preflight / gen-keystore / set-gh-secrets / lint-skill
│   └── assets/
│       ├── liquid/                 # 7 个 .kt（与 component/ 逐字节一致）+ 2 段 snippet
│       ├── signing-config.gradle.kts.snippet
│       └── workflow-build-apk.yml  # workflow 镜像（改包名时要同步第 118 行）
└── .github/workflows/
    ├── build-apk.yml               # 编译 + 签名 + 校验 + emulator 冒烟 + 建 Release
    ├── test.yml                    # Robolectric JVM 截图回归
    └── dependency-review.yml       # 逐依赖比对
```

UI 写在 `shared/src/commonMain/kotlin/top/yukonga/miuixapptemplate/App.kt`，用 MIUIX 组件（`TopAppBar` / `Scaffold` / `Card` / `Switch` / `Slider` / `Button` / `Text`）+ `MiuixTheme` 主题。把这段 Composable 换成你自己的界面即可。
