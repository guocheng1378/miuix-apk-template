# CI workflow（GitHub Actions）

模板：`assets/workflow-build-apk.yml`。落盘位置 `.github/workflows/build-apk.yml`。
以下描述本仓库**当前那份** workflow 的真实形态（2026-09-02 读取）。
仓库里那份是权威，模板只是起点——两者冲突时以 `.github/workflows/build-apk.yml` 为准。

## 结构：两个 job

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
- 冒烟判定四项：安装返回 `Success`、`am start -W` 返回 `Status: ok`、
  `pidof` 非空（没闪退）、logcat 无 `FATAL EXCEPTION|Fatal signal|ANR in|E/AndroidRuntime`。
  截图只断言「画没画出来」——`-gpu swiftshader_indirect` 是软件光栅化，
  RenderEffect 模糊质感与真机 GPU 差异极大，**不能**当像素级视觉基线做 diff。
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

`api.github.com` 匿名配额只有 60/小时，很容易打满（403 + `x-ratelimit-remaining: 0`）。
上面这种 `releases/latest` 重定向法更省。

本仓库当前用到的版本（2026-09 实测文件内容）：`actions/checkout@v7`、
`actions/setup-java@v6`、`actions/download-artifact@v8`、`actions/upload-artifact@v7`、
`actions/cache/restore@v6`、`actions/cache/save@v6`、`gradle/actions/setup-gradle@v6`、
`softprops/action-gh-release@v3`、`reactivecircus/android-emulator-runner@v2`。

## 未配 Secrets 时的产物语义

**产物是 `app-release-unsigned.apk`**——不是 debug 签名的可安装包。
它无法直接 `adb install`，需自行 zipalign + `apksigner` 才能安装/上架。
配齐四条 Secrets 才产出已签名 Release APK。

## 版本号自动化（与 workflow 耦合）

`app/build.gradle.kts` 不再手工递增版本号，优先级
`VERSION_CODE`/`VERSION_NAME` 环境变量 > CI 派生值 > 本地兜底（`2` / `"1.0.2"`）：

- `versionCode` 取 `GITHUB_RUN_NUMBER`，并与兜底值取 **`max`**——
  `GITHUB_RUN_NUMBER` 只在单个 workflow 文件内递增，换 workflow 会从 1 重新计数，
  直接取用会让 versionCode 倒退（Google Play 拒收）。重跑同一次 run 该值不变，可复现。
- `versionName` 在 `GITHUB_REF_TYPE == "tag"` 时取 tag 名去掉前导 `v`，
  所以发版只需打 tag，不必改文件。

## 本地构建

需自备 Gradle 9.x + Android SDK，或补交 `gradlew` 与 `gradle/wrapper/gradle-wrapper.jar`。
本机无 JDK 时**不要**尝试本地构建，直接推分支让 CI 跑——但推送前必须确认环境有
GitHub 凭证（PAT / ssh key），否则连 push 都做不到，也就无法触发 CI。
