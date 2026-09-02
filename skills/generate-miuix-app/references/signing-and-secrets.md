# 无 JDK 环境下补齐签名

本机常常没有 `java` / `keytool` / `apksigner`。签名材料照样能产出并全自动写入 Secrets，
全流程不需要 Android SDK。

## 四条 Secrets

| GitHub Secret | 内容 |
|---|---|
| `SIGNING_KEY` | keystore 文件的 base64（`base64 -w0`，单行无换行） |
| `KEYSTORE_PASSWORD` | keystore 口令 |
| `KEY_ALIAS` | 条目别名 |
| `KEY_PASSWORD` | 私钥口令（openssl 路径下与 keystore 口令相同） |

> **Secret 名不等于 Gradle 侧变量名**（`KEYSTORE_PASSWORD` → `KEYSTORE_PASS`，
> `KEYSTORE_PATH` 不是 Secret）。完整映射表在 `ci-workflow.md`，改任何一侧都要同步另一侧。

## 1. 用 openssl 产 PKCS12（替代 keytool）

一条命令：

```bash
bash scripts/gen-keystore.sh --alias mykey --subject "/C=CN/O=myorg/CN=my-release" --outdir ./keystore
```

参数与缺省值（实测脚本源码）：`--alias`（默认 `release`）、`--subject`
（默认 `/C=CN/O=unknown/CN=android-release`）、`--days`（默认 `10950`）、
`--outdir`（默认 `./keystore`）、`--password`。
**不传 `--password` 时脚本用 `openssl rand -hex 16` 随机生成**并写进 `password.txt`，
所以手工等价步骤里的 `<口令>` 要么自己定、要么去 `password.txt` 读。

手工等价步骤：

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -days 10950 -nodes \
  -keyout key.pem -out cert.pem -subj "/C=CN/O=myorg/CN=my-release"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out release.p12 \
  -name mykey -passout pass:'<口令>'
base64 -w0 release.p12          # → SIGNING_KEY 的值
```

脚本输出 5 个文件：`cert.pem` / `key.pem` / `release.p12` / `password.txt` /
**`alias.txt`**，并把 base64 结果单独打印到 stdout 供直接粘进 Secrets。
`alias.txt` 是下一步脚本读 `KEY_ALIAS` 的来源，别漏。
`-name` 决定 PKCS12 里的 alias，必须与 `KEY_ALIAS` 一致，否则 AGP 找不到条目——
脚本末尾会用该口令 `openssl pkcs12 -info -noout` 自校验一次。

> **走 PKCS12 时 `app/build.gradle.kts` 的 signingConfig 必须显式
> `storeType = "PKCS12"`**，否则 AGP 按默认 JKS 读取会失败。这是本条路径唯一的额外代价。

有 JDK 时的备选（产物是 JKS，此时**不需要**写 `storeType`）：

```bash
keytool -genkeypair -v -keystore release.jks -alias mykey \
  -keyalg RSA -keysize 2048 -validity 10950 \
  -storepass '<口令>' -keypass '<口令>' \
  -dname "CN=my-release, OU=dev, O=myorg, L=city, ST=state, C=CN"
base64 -w0 release.jks
```

## 2. 用 API 写 Secrets（替代网页手点）

```bash
python3 scripts/set-gh-secrets.py --repo <owner>/<repo> --token-env GH_TOKEN \
  --from-dir ./keystore
```

**脚本没有 `--alias` 参数**——别照记忆加一个，argparse 会直接报错退出。
`--from-dir` 一次写四条 Secrets，取值全部来自 `gen-keystore.sh` 的输出目录：
`SIGNING_KEY`（`release.p12` 的 base64）、`KEYSTORE_PASSWORD` 与 `KEY_PASSWORD`
（都取 `password.txt`，openssl 路径下两者相同）、`KEY_ALIAS`（取 `alias.txt`，
**文件缺失时缺省 `release`**）。单条写入用 `--set NAME=VALUE`（可重复，
按第一个 `=` 切分）。`--token-env` 默认 `GH_TOKEN`。

流程（脚本内部实现，理解它才能排错）：

1. `GET /repos/{o}/{r}/actions/secrets/public-key` → 取 `key_id` 与 base64 公钥。
2. 用 NaCl **sealed box** 加密明文：PyNaCl `nacl.public.SealedBox(pubkey).encrypt(plain)`。
   **注意是 `SealedBox` 不是 `Box`**——`Box` 需要双方私钥，GitHub 只提供公钥，
   用错类在编译期看不出来，运行期才报参数错误。
3. `PUT /repos/{o}/{r}/actions/secrets/{NAME}`，body
   `{"key_id": <步骤1的key_id>, "encrypted_value": <base64密文>}`。
   密文要 `base64.b64encode(...)` 后再放 JSON。
4. HTTP **201 或 204** 都算成功（首次创建 201，覆盖已存在的是 204）。

权限：classic PAT 需 `repo`（private 仓库）或 `admin:repo` 级；fine-grained PAT 需
`Administration: Write`。403 通常是权限不足而不是加密写错——先看响应 body 里的 message。

`pynacl` 缺失时脚本会打印 `pip install pynacl` 并退出。**装在 venv 里**，
不要污染系统 Python。

## 3. CI 里的签名校验兜底

主场在 `ci-workflow.md`（build job 的 `Verify APK signature` 步骤）：产物文件名含
`unsigned` 即 `exit 1`，再 `apksigner verify --print-certs` 打印证书指纹。
效果是「Secrets 没生效」当场红，而不是把装不上的包挂到 Release 页上。

## 4. 备份与泄露面

- keystore 与口令要**异地备份**。丢了它，同一 `applicationId` 再也无法覆盖升级到已装用户机上
  ——只能换包名重新发。
- 仓库是 **public** 时绝不要把 keystore 当 workflow artifact 上传：artifact 可被任何
  持 token 者下载，等于泄露私钥。只走 Secrets。
- `.gitignore` 需含 `*.jks` / `*.keystore` / `*.p12` / `local.properties`
  （本模板仓库已含）。
- 本地开发把口令放 `local.properties`（`signingProp` 的回退路径），不要放
  `gradle.properties`——后者常被误提交。
- 绝不回显用户提供的 token。PAT 一旦明文出现在对话里，交付后立即建议用户撤销。
