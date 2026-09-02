#!/usr/bin/env python3
"""用 GitHub REST API 加密写入 Actions Secrets（替代网页手点，可全自动）。

流程：
  1. GET /repos/{o}/{r}/actions/secrets/public-key  -> key_id + base64 公钥
  2. NaCl **sealed box** 加密明文（PyNaCl nacl.public.SealedBox）
     注意是 SealedBox 不是 Box：Box 需要双方私钥，GitHub 只公开公钥。
     用错类在 import 阶段看不出来，要到 encrypt 才报错。
  3. PUT /repos/{o}/{r}/actions/secrets/{NAME}  body {"key_id":..,"encrypted_value":..}
     201（首次创建）与 204（覆盖已存在）都算成功。

依赖：pip install pynacl（建议装进 venv，别污染系统 Python）。
Token 权限：classic PAT 需 repo / admin:repo；fine-grained 需 Administration: Write。
403 一般是权限不足，不是加密写错——先看响应 body 的 message。

用法：
  # 从 gen-keystore.sh 的输出目录一次性写四条签名 Secrets
  python3 set-gh-secrets.py --repo owner/name --from-dir ./keystore

  # 或手工指定单条
  python3 set-gh-secrets.py --repo owner/name --set MY_SECRET=hunter2

Token 从环境变量读（默认 GH_TOKEN），不作为命令行参数——argv 会被 ps 和其他用户看到。
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"


def die(msg, code=1):
    print(f"错误: {msg}", file=sys.stderr)
    sys.exit(code)


def require_pynacl():
    try:
        from nacl import public  # noqa: F401
    except ImportError:
        die(
            "缺少 pynacl。请装进虚拟环境后重试：\n"
            "    python3 -m venv .venv && . .venv/bin/activate && pip install pynacl\n"
            "（不要直接 pip install 到系统 Python）"
        )


def request(method, url, token, body=None):
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        return e.code, {"_raw": raw}
    except urllib.error.URLError as e:
        die(f"网络不可达 {url}: {e.reason}")


def get_public_key(repo, token):
    status, payload = request(
        "GET", f"{API}/repos/{repo}/actions/secrets/public-key", token
    )
    if status != 200:
        hint = ""
        if status in (401, 403):
            hint = "（token 无效或权限不足：classic PAT 需 repo/admin:repo，fine-grained 需 Administration: Write）"
        elif status == 404:
            hint = "（仓库不存在，或 token 看不到该仓库）"
        die(f"取 public-key 失败 HTTP {status}{hint}\n{payload.get('_raw', payload)}")
    for field in ("key_id", "key"):
        if field not in payload:
            die(f"public-key 响应缺少 {field}: {payload}")
    return payload["key_id"], payload["key"]


def seal(pubkey_b64, plaintext):
    from nacl import public

    box = public.SealedBox(public.PublicKey(base64.b64decode(pubkey_b64)))
    # 密文必须再 base64 一次才能放进 JSON 字符串字段
    return base64.b64encode(box.encrypt(plaintext.encode("utf-8"))).decode("ascii")


def put_secret(repo, name, token, key_id, sealed):
    status, payload = request(
        "PUT",
        f"{API}/repos/{repo}/actions/secrets/{name}",
        token,
        {"key_id": key_id, "encrypted_value": sealed},
    )
    # 201 = 首次创建，204 = 覆盖已存在的同名 secret。两者都是成功。
    return status in (201, 204), status, payload


def collect_from_dir(path):
    """把 gen-keystore.sh 的输出目录映射成四条签名 Secrets。"""
    if not os.path.isdir(path):
        die(f"--from-dir 指向的目录不存在: {path}")

    def read_text(name):
        p = os.path.join(path, name)
        if not os.path.isfile(p):
            return None
        with open(p, "r", encoding="utf-8") as f:
            return f.read().strip()

    p12 = os.path.join(path, "release.p12")
    if not os.path.isfile(p12):
        die(f"{path} 里没有 release.p12。先用 scripts/gen-keystore.sh 生成，或改用 --set 手工指定")
    with open(p12, "rb") as f:
        signing_key = base64.b64encode(f.read()).decode("ascii")

    password = read_text("password.txt")
    if not password:
        die(f"{path}/password.txt 缺失或为空——没有口令无法签名")
    alias = read_text("alias.txt") or "release"

    # openssl 路径下 keystore 口令与私钥口令相同（-passout 只设了一个）
    return {
        "SIGNING_KEY": signing_key,
        "KEYSTORE_PASSWORD": password,
        "KEY_ALIAS": alias,
        "KEY_PASSWORD": password,
    }


def main():
    ap = argparse.ArgumentParser(
        description="加密写入 GitHub Actions Secrets（NaCl sealed box）"
    )
    ap.add_argument("--repo", required=True, help="owner/name，例如 guocheng1378/miuix-apk-template")
    ap.add_argument("--token-env", default="GH_TOKEN", help="存放 token 的环境变量名（默认 GH_TOKEN）")
    ap.add_argument("--from-dir", help="gen-keystore.sh 的输出目录，一次性写 SIGNING_KEY/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD")
    ap.add_argument(
        "--set",
        action="append",
        default=[],
        metavar="NAME=VALUE",
        help="手工指定一条 Secret，可重复。值里含 = 时只按第一个 = 切分",
    )
    args = ap.parse_args()

    if "/" not in args.repo or args.repo.count("/") != 1:
        die(f"--repo 必须是 owner/name 形式，收到: {args.repo}")

    require_pynacl()

    token = os.environ.get(args.token_env)
    if not token:
        die(
            f"环境变量 {args.token_env} 为空。请 export {args.token_env}=<PAT> 后重试。\n"
            "token 不要写成命令行参数——argv 对本机其他用户可见。"
        )

    secrets = {}
    if args.from_dir:
        secrets.update(collect_from_dir(args.from_dir))
    for item in args.set:
        if "=" not in item:
            die(f"--set 需要 NAME=VALUE 形式，收到: {item}")
        name, value = item.split("=", 1)
        secrets[name.strip()] = value

    if not secrets:
        die("没有任何要写入的 Secret。用 --from-dir 或至少一个 --set NAME=VALUE")

    key_id, pubkey = get_public_key(args.repo, token)
    print(f"取到 key_id={key_id}（公钥不回显）")

    failed = []
    for name in sorted(secrets):
        try:
            sealed = seal(pubkey, secrets[name])
        except Exception as e:  # 口令/明文异常时不要打印明文
            die(f"加密 {name} 失败: {type(e).__name__}: {e}")
        ok, status, payload = put_secret(args.repo, name, token, key_id, sealed)
        if ok:
            print(f"  {name}: HTTP {status} OK（{'新建' if status == 201 else '覆盖'}）")
        else:
            msg = payload.get("message") if isinstance(payload, dict) else payload
            print(f"  {name}: HTTP {status} 失败 -> {msg}", file=sys.stderr)
            failed.append(name)

    if failed:
        print(
            f"\n失败 {len(failed)} 条: {', '.join(failed)}\n"
            "403 多为 token 权限不足；404 多为仓库名写错。",
            file=sys.stderr,
        )
        sys.exit(1)

    print(
        f"\n已写入 {len(secrets)} 条 Secrets。\n"
        "提醒：token 用完请立即撤销；仓库是 public 时只走 Secrets，"
        "绝不要把 keystore 当 workflow artifact 上传。"
    )


if __name__ == "__main__":
    main()
