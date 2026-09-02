#!/usr/bin/env python3
"""generate-miuix-app skill 结构性校验。

检查四类问题：
  1. frontmatter 形状（name / description 存在、name 与目录名一致、长度限制）
  2. 引用完整性（文档里出现的相对路径、references/ 与 assets/ 文件是否真实存在）
  3. 数字一致性（SKILL.md 引用的条数、文件数与实际是否吻合）
  4. 常见漂移（「未核实」标记、被禁的包名/函数名是否又写回来了）
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
errors, warns = [], []


def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


# ---------- 1. frontmatter ----------
skill_md = os.path.join(ROOT, "SKILL.md")
if not os.path.isfile(skill_md):
    print("FATAL 缺 SKILL.md")
    sys.exit(1)

raw = read(skill_md)
m = re.match(r"^---\n(.*?)\n---\n", raw, re.S)
if not m:
    errors.append("SKILL.md 没有 YAML frontmatter（必须以 --- 包裹）")
    body = raw
else:
    fm, body = m.group(1), raw[m.end():]
    name = re.search(r"^name:\s*(.+?)\s*$", fm, re.M)
    desc = re.search(r"^description:\s*(.+?)\s*$", fm, re.M)
    if not name:
        errors.append("frontmatter 缺 name")
    else:
        v = name.group(1).strip("\"'")
        if v != os.path.basename(os.path.abspath(ROOT)):
            errors.append(f"name={v!r} 与目录名 {os.path.basename(os.path.abspath(ROOT))!r} 不一致")
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", v):
            errors.append(f"name={v!r} 不符合 kebab-case")
        if len(v) > 64:
            errors.append(f"name 长度 {len(v)} > 64")
    if not desc:
        errors.append("frontmatter 缺 description")
    else:
        d = desc.group(1).strip("\"'")
        if len(d) < 40:
            errors.append(f"description 过短（{len(d)} 字符），不足以触发")
        if len(d) > 1024:
            errors.append(f"description 长度 {len(d)} > 1024")
    allowed = {"name", "description", "allowed-tools", "license", "metadata", "version"}
    for key in re.findall(r"^([A-Za-z][A-Za-z0-9_-]*):", fm, re.M):
        if key not in allowed:
            warns.append(f"frontmatter 非标准键 {key!r}")

# ---------- 2. 引用完整性 ----------
all_files = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git", "__pycache__")]
    for fn in filenames:
        all_files.append(os.path.relpath(os.path.join(dirpath, fn), ROOT))

docs = [f for f in all_files if f.endswith(".md")]
path_re = re.compile(r"(?:references|assets|scripts)/[A-Za-z0-9_./-]+")
for d in docs:
    text = read(os.path.join(ROOT, d))
    for ref in set(path_re.findall(text)):
        ref = ref.rstrip(".,)`'\"")
        if any(ch not in "/.-" for ch in ref) and not re.search(r"\.(md|kt|sh|yml|yaml|json|snippet|properties)$", ref):
            continue
        if os.path.exists(os.path.join(ROOT, ref)):
            continue
        if os.path.exists(os.path.join(ROOT, d, ref)):
            continue
        # 允许指向仓库根（skill 目录之外）的路径
        if os.path.exists(os.path.join(ROOT, "..", "..", ref)):
            continue
        errors.append(f"{d} 引用了不存在的 {ref}")

# 反向：有文件但没人引用
referenced = set()
for d in docs:
    for ref in path_re.findall(read(os.path.join(ROOT, d))):
        referenced.add(ref.rstrip(".,)`'\""))
for f in all_files:
    if f == "SKILL.md" or not os.path.splitext(f)[1]:
        continue
    if f not in referenced and not any(r.endswith(f) or f.endswith(r) for r in referenced):
        warns.append(f"{f} 未被任何文档引用（孤儿文件？）")

# ---------- 3. 数字一致性 ----------
sk = read(skill_md)
for cnt_txt, actual_glob, label in []:
    pass

liq_dir = os.path.join(ROOT, "assets", "liquid")
if os.path.isdir(liq_dir):
    n_kt = sum(1 for dp, dn, fn in os.walk(liq_dir) for x in fn if x.endswith(".kt"))
    n_sn = sum(1 for dp, dn, fn in os.walk(liq_dir) for x in fn if x.endswith(".snippet"))
    for d in docs:
        t = read(os.path.join(ROOT, d))
        for mm in re.finditer(r"(\d+)\s*个\s*(?:\.kt\s*)?(?:源文件|文件|源码文件)", t):
            if "liquid" in t[max(0, mm.start() - 200):mm.start()] and int(mm.group(1)) != n_kt:
                warns.append(f"{d}: 液态玻璃文件数写 {mm.group(1)}，实际 {n_kt}")
    print(f"INFO assets/liquid: {n_kt} 个 .kt + {n_sn} 个 snippet")

# ---------- 4. 禁词回潮 ----------
BANNED = {
    "kmp.navigation": "导航包名应为 nav.core",
    "rememberMiuixScrollBehavior": "该函数不存在，应为 MiuixScrollBehavior()",
    "nestedScroll.connection": "成员名应为 nestedScrollConnection",
    "PreferenceCategory": "miuix 无此组件（作为误用示例引用时须放在坑表里）",
    "LargeTopAppBar": "miuix 无此组件",
}
for d in docs + [f for f in all_files if f.endswith((".kt", ".sh", ".snippet"))]:
    t = read(os.path.join(ROOT, d))
    for line_no, line in enumerate(t.splitlines(), 1):
        for bad, why in BANNED.items():
            if bad in line:
                # 坑表 / 反例语境放行：整行含「误用」「不是」「没有」「错」「应为」「→」等标记
                if re.search(r"误用|不是|没有|应为|错|禁止|不要|无此|✗|→|❌|不存在", line):
                    continue
                warns.append(f"{d}:{line_no} 出现 {bad}（{why}）且不在反例语境")

print(f"\n文档 {len(docs)} 个，skill 内文件 {len(all_files)} 个")
for w in warns:
    print("WARN ", w)
for e in errors:
    print("ERROR", e)
print(f"\n== ERROR={len(errors)} WARN={len(warns)} ==")
sys.exit(1 if errors else 0)
