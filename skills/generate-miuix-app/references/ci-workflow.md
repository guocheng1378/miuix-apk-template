# CI workflow（GitHub Actions）

模板：`assets/workflow-build-apk.yml`。落盘位置 `.github/workflows/build-apk.yml`。
以下描述本仓库**当前那份** workflow 的真实形态（2026-09-02 读取）。
仓库里那份是权威，模板只是起点——两者冲突时以 `.github/workflows/build-apk.yml` 为准。

## 仓库里其实有三套 workflow

`assets/` 只镜像了 `build-apk.yml` 一份，另两份没有模板，照抄时直接读仓库文件：

| 文件 | 触发 | 干什么 |
|---|---|---|
| `build-apk.yml` | `push.tags: ["v*"]` + `workflow_dispatch` | 构建 + 签名 + 模拟器冒烟 + 发 Release |
| `test.yml` | `pull_request` + `push: master` | JVM 截图回归（Robolectric + Roborazzi），`timeout-minutes: 30` |
| `dependency-review.yml` | `pull_request` + `push: master` | Gradle 依赖图提交 + Dependency Review，`fail-on-severity: moderate` |

`test.yml` 用 `gradle :shared:check -Proborazzi.test.record=true`（而不是猜 roborazzi 的
record 任务名），并带一步 `Ensure screenshots were produced`——找不到任何 PNG 就 `exit 1`，
防「预览扫描没命中却全绿」。派生新 app 时若沿用截图回归，这两点都要复刻。

2026-09-02 实测：`assets/workflow-build-apk.yml` 与 `.github/workflows/build-apk.yml`
剥掉注释和空行后 `diff` 为空，即模板与仓库当前同步。改仓库那份时记得同步镜像，否则
生成新工程会拿到旧版。

## `build-apk.yml` 结构：两个 job

```
build  ──►  smoke（needs: build）
```

### `build`

- 触发：`on: push.tags: ["v*"]` + `workflow_dispatch`
- 顶层 **`permissions: contents: write`**
- 步骤：
  1. `actions/checkout@v7`
  2. `actions/setup-java@v6`（`distribution: zulu`，`java-version: "21"`）
  3. `gradle/actions/setup-gradle@v6`
  4. Decode signing key（shell 内判断，见下）
  5. `gradle :app:assembleRelease --no-daemon`
  6. **Verify APK signature**（`unsigned` 即 `exit 1`，再 `apksigner verify --print-certs`）
  7. `actions/upload-artifact@v7`（name `app-release-apk`）
  8. `softprops/action-gh-release@v3`，`if: startsWith(github.ref, 'refs/tags/')`，
     `generate_release_notes: true`

> `action-gh-release` 现在是 **v3**（不是 v2）。v3 相比 v2 主要是运行时升到 node24
> 并规范化 `tag_name` 输入。这类大版本每年都在动——**照抄前先核实**，方法见下。

### `smoke`

`needs: build`，`timeout-minutes: 45`，`permissions: contents: read`。
在真头模拟器上安装 build 产出的**同一个 APK** 并拉起 `MainActivity`。要点：

- `Enable KVM group perms`（udev 规则）→ `setup-java@v6` →
  `actions/download-artifact@v8` → `actions/cache/restore@v6`（AVD 快照）→
  未命中时先跑一次「只开机不测」生成快照 → `reactivecircus/android-emulator-runner@v2`
  → `upload-artifact`（证据，`if: always()`）→ `actions/cache/save@v6`
- **`api-level: 34`**：工程 `minSdk 24`，但 `miuix-blur` 要求 33（靠 `overrideLibrary`
  过合并检查），低于 33 走不到液态玻璃渲染路径，冒烟没意义；34 也避开 35 起的 16KB 页镜像变体。
- **`arch` 必须显式 `x86_64`**：该 action 默认 `x86`，而 android-34 已不再提供 x86 镜像。
- 快照缓存拆成 `cache/restore` + `cache/save` 两步，而不是单个 `actions/cache`：
  `cache` 的 post 步骤带 `post-if: success()`，冒烟一挂就不存快照——
  而首次跑恰恰最贵（下 ~1GB 镜像 + 冷启动生成快照），失败了也得存下来。
- 冒烟逻辑写成 `$RUNNER_TEMP/smoke.sh` 文件，`script:` 里只放一行调用。
  原因：`android-emulator-runner` 的 script parser 会把 `script` **按行拆成数组、
  每行单独 `sh -c`**，跨行的 `if/fi`、`case`、变量全部失效。
- 冒烟判定**五项**（逐项 `FAIL=1`，最后统一判定，中途失败也先把证据收全）：
  1. `adb install -r -g` 退出码为 0 **且** 输出含 `Success`；
  2. `am start -W` 输出含 `Status: ok`；
  3. `screencap -p` 输出文件非空（`-s`）**且不是单色空白屏**（见下）；
  4. `pidof <包名>` 非空（没启动即闪退）；
  5. logcat 无崩溃特征，正则 `FATAL EXCEPTION|Fatal signal|ANR in |E/AndroidRuntime|E AndroidRuntime`
     —— 斜杠版和空格版**都要写**：`logcat -v time` 输出 `E/AndroidRuntime`，
     默认的 threadtime 格式输出 `E AndroidRuntime`，只写一种会漏。
     `ANR in` 后面带空格，避免匹配到 `ANR in` 之外的词。
     崩溃特征还要**按归属过滤**（本行带包名 / 下一行 `Process: <包名>` / tag 括号里的
     pid 属于本包，三者命中任一即算本 app），否则同窗口内别的系统进程崩溃会随机判红。
  判定前先 `adb logcat -c` 清缓冲，让崩溃窗口只覆盖「安装→预热→启动→渲染」这段。
  截图只断言「画没画出来 / 是不是单色」——`-gpu swiftshader_indirect` 是软件光栅化，
  RenderEffect 模糊质感与真机 GPU 差异极大，**不能**当像素级视觉基线做 diff。
- **截图判据不能只看非空**：实测一次判红里 `screen.png` 有 1440x3120、24472 bytes，
  但整屏只有一个颜色 `000000`（ANR 后 activity 重启，截图正好撞在过渡帧上）。
  补了一层像素判定：runner 上**不保证有 Pillow**，用 python3 标准库（`struct` + `zlib`）
  自己解 IHDR/PLTE/IDAT、逐行还原 5 种 filter，按 40px 网格**逐行错相 17** 采样
  （固定网格会和周期规整的图案整步混叠，把真内容误判成空白屏），输出
  「唯一颜色数 / 采样点数」，**唯一颜色 ≤ 1 或采样点 < 10 即判空白屏**。
  解析器自己出问题（python 缺失、PNG 是不支持的变体如隔行/16-bit）时**退回旧的
  「非空」判据**而不是硬 FAIL——判据退化只是少一层保险，硬红会把工具链问题
  算成 app 缺陷。实现形式：外层 `<<'SMOKE_EOF'` 里再套一个 `<<'PY'`，运行时由
  smoke.sh 自己落成 `$RUNNER_TEMP/blankpng.py`；两个分隔符不同名所以嵌套合法。
- **预热**：install 之后、判定用的那次 `am start` 之前，插一段 `cmd package compile
  -m speed -f <包名>`（失败只打印不判红）+ 一次抛弃式 `am start -W`（`|| true`，
  成败不参与判定，只打印 `TotalTime` 供对照）+ `sleep 5` + `force-stop`。
  动机：冷 AVD 首启只做 verify 级 dexopt（实测 `dex2oatWallTimeMillis=7387`、
  `TotalTime 7653ms`），主线程被钉住 → `FocusEvent` 输入分发超时 → `ANR in`，
  那是**环境冷启动慢不是 app 缺陷**。机制与对照实验见 `references/pitfalls.md` J1。
- 前台 activity 只观测不判定（`dumpsys` 字段格式随版本变，硬断言会假失败）。

### 有意的取舍：冒烟失败时 Release 已经发出去了

`Create GitHub Release` 是 build job 的最后一步，smoke 通过 `needs: build` 排在它后面。
理由：APK 已过 `apksigner` 校验，冒烟挂了通常是「运行环境/渲染」问题，
不该把用户已能下载的 Release 一起拖回未发布状态；但 smoke job 本身必须红，
在页面上留下明确的失败信号。若哪天要改成「冒烟不过就不发版」，
把 Release 步骤挪进一个 `needs: [build, smoke]` 的 publish job 即可。

## 三个会让 workflow 直接失效的坑

### 1. `permissions: contents: write`

缺省 `GITHUB_TOKEN` 只有 `contents: read`，创建 Release 会 403
`Resource not accessible by integration`。本仓库提交 `f2d4377` 就是修这个的——
说明它真的会踩。

### 2. `secrets.*` 不能出现在 step 级 `if:`

step 的 `if:` 拿不到 `secrets` 上下文，写上去导致**整个 workflow 被解析成 0 个 job**
（不报错、静默什么都不跑，最难查）。判断必须写进 shell step 内部：

```yaml
- name: Decode signing key
  env:
    SIGNING_KEY: ${{ secrets.SIGNING_KEY }}
  run: |
    if [ -n "$SIGNING_KEY" ]; then
      echo "$SIGNING_KEY" | base64 -d > "$GITHUB_WORKSPACE/keystore.p12"
    fi
```

### 3. 构建命令是 `gradle`，不是 `./gradlew`

仓库未提交 wrapper jar，由 `setup-gradle` 提供与 AGP 9.x 匹配的 Gradle 9.x 并放进 PATH。
**不要**现场 `gradle wrapper --gradle-version 8.13`——版本错配，报出来的错还指向别处。

## Secret 名 ≠ Gradle 侧环境变量名

这是最容易配错的一处。Secret 叫 `KEYSTORE_PASSWORD`，但 `build.gradle.kts` 里
`signingProp` 读的变量叫 **`KEYSTORE_PASS`**，靠 workflow 的 `env:` 做映射：

| GitHub Secret | workflow `env:` 变量 | 说明 |
|---|---|---|
| `SIGNING_KEY` | `SIGNING_KEY` | base64 keystore；shell 里 `base64 -d` 成 `keystore.p12` |
| — | `KEYSTORE_PATH` | 不是 Secret，直接写 `${{ github.workspace }}/keystore.p12` |
| `KEYSTORE_PASSWORD` | **`KEYSTORE_PASS`** | 名字不一致 |
| `KEY_ALIAS` | `KEY_ALIAS` | |
| `KEY_PASSWORD` | `KEY_PASSWORD` | openssl 路径下与 keystore 口令相同 |

改任何一侧都要同步另一侧，否则表现为「Secrets 明明配了却没签名」。

## Action 版本必须真实存在

不要凭记忆写。核实方法（匿名请求，不占 API 配额）：

```bash
curl -sSL -o /dev/null -w '%{redirect_url}\n' \
  https://github.com/actions/checkout/releases/latest
# 末尾 .../tag/v7 即最新大版本
```

`api.github.com` 匿名配额只有 60/小时，很容易打满；上面这种 `releases/latest` 重定向法
不占配额（配额细节见 `verification.md`）。

本仓库三套 workflow 当前用到的版本（2026-09-02 实测文件内容）：
`actions/checkout@v7`、`actions/setup-java@v6`、`actions/download-artifact@v8`、
`actions/upload-artifact@v7`、`actions/cache/restore@v6`、`actions/cache/save@v6`、
`gradle/actions/setup-gradle@v6`、`softprops/action-gh-release@v3`、
`reactivecircus/android-emulator-runner@v2`；`dependency-review.yml` 另用
`gradle/actions/dependency-submission@v6`（带 `gradle-version: '9.7.1'`，因为仓库没有
wrapper jar）和 `actions/dependency-review-action@v5`。

## 未配 Secrets 时的产物语义

**产物是 `app-release-unsigned.apk`**——不是 debug 签名的可安装包。
它无法直接 `adb install`，需自行 zipalign + `apksigner` 才能安装/上架。
配齐四条 Secrets 才产出已签名 Release APK。

## 版本号自动化（与 workflow 耦合）

发版只需打 `v*` tag，不必改文件：`versionCode` 取 `GITHUB_RUN_NUMBER` 并与兜底值取
`max`，`versionName` 在 `GITHUB_REF_TYPE == "tag"` 时取 tag 名去掉前导 `v`。
完整取值优先级与「为什么必须取 max」的解释在 `stack-and-build.md`（构建脚本侧的主场）。

## 本地构建

需自备 Gradle 9.x + Android SDK，或补交 `gradlew` 与 `gradle/wrapper/gradle-wrapper.jar`。
环境里没有 JDK 时不要尝试本地构建，直接推分支让 CI 跑（前提：有 GitHub 凭证能 push）。
这条判断的主场在 `verification.md`。
