#!/usr/bin/env python3
"""仓库卫生检查（无网络、无设备、无 Chromium 源码依赖）。

    python3 tools/verify/check_repo.py

检查项：
  * 补丁：编号单调递增 / 不重复 / `--- a/` 头 / 被 patches/README.md 覆盖
  * 文档：所有相对 Markdown 链接指向真实文件（跳过 http、锚点）
  * 索引：docs/*.md 与 docs/adr/*.md 都被索引
  * skills：`.agents/skills/*/SKILL.md` frontmatter 有 name+description，name 与目录一致
  * 卫生：`scripts/**/*.sh` 有可执行位；禁止跟踪 APK/out/artifacts；Markdown 以换行结尾
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FAILS: list[str] = []
OKS = 0


def ok(msg: str) -> None:
    global OKS
    OKS += 1
    print(f"ok   {msg}")


def bad(msg: str) -> None:
    FAILS.append(msg)
    print(f"FAIL {msg}")


def tracked(*patterns: str) -> list[str]:
    """Tracked + untracked-but-not-ignored files, so the check also works before
    the first commit of a new file (and in CI, where everything is tracked)."""
    out = subprocess.run(
        ["git", "-C", ROOT, "ls-files", "--cached", "--others", "--exclude-standard", *patterns],
        capture_output=True, text=True, check=True).stdout
    return sorted(p for p in out.splitlines() if p)


def rel(path: str) -> str:
    return os.path.join(ROOT, path)


# --- patches ---------------------------------------------------------------
def check_patches() -> None:
    patches = sorted(tracked("patches/*.patch"))
    if not patches:
        bad("patches/ 为空（至少应有 0002）")
        return

    nums: list[int] = []
    readme = open(rel("patches/README.md"), encoding="utf-8").read()
    for p in patches:
        name = os.path.basename(p)
        m = re.match(r"^(\d{4})-", name)
        if not m:
            bad(f"{p}: 文件名必须是 NNNN-*.patch")
            continue
        nums.append(int(m.group(1)))
        first = open(rel(p), encoding="utf-8", errors="replace").readline().strip()
        if not (first.startswith("--- a/") or first.startswith("diff --git ")):
            bad(f"{p}: 首行必须是 '--- a/<path>'（当前: {first[:60]}）")
        # The README table lists the number + short name, not the .patch suffix.
        if not re.search(rf"(?<!\d){m.group(1)}(?!\d)", readme):
            bad(f"{p}: 未在 patches/README.md 中登记")
    if nums != sorted(set(nums)):
        bad(f"patches/: 编号必须严格递增且不重复（当前: {nums}）")
    if nums and len(set(nums)) == len(nums):
        ok(f"patches/: {len(nums)} 个，编号递增 {nums[0]}..{nums[-1]}，README 覆盖完整")

    listed = sorted({int(n) for n in re.findall(r"(?m)^\|\s*(\d{4})\s*\|", readme)})
    missing = [n for n in listed if n not in nums]
    if missing:
        bad(f"patches/README.md 列出了不存在的补丁编号: {missing}")


# --- docs links ------------------------------------------------------------
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def check_links() -> None:
    files = [p for p in tracked("*.md") if "__pycache__" not in p]
    checked = 0
    broken: list[str] = []
    for f in files:
        text = open(rel(f), encoding="utf-8", errors="replace").read()
        for target in LINK_RE.findall(text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#", 1)[0].strip()
            if not target:
                continue
            path = os.path.normpath(os.path.join(os.path.dirname(rel(f)), target))
            checked += 1
            if not os.path.exists(path):
                broken.append(f"{f} -> {target}")
    if broken:
        for b in broken:
            bad(f"失效链接: {b}")
    if checked and not broken:
        ok(f"Markdown 链接：{checked} 个相对链接全部有效（{len(files)} 个文件）")


# --- docs index ------------------------------------------------------------
def check_docs_index() -> None:
    # git pathspecs match recursively; keep only top-level docs/*.md here,
    # ADR files are indexed by docs/adr/README.md instead.
    docs = sorted(os.path.basename(p) for p in tracked("docs/*.md")
                  if p.count("/") == 1)
    index = open(rel("docs/README.md"), encoding="utf-8").read()
    adr_index = open(rel("docs/adr/README.md"), encoding="utf-8").read() \
        if os.path.exists(rel("docs/adr/README.md")) else ""
    missing = [d for d in docs
               if d not in ("README.md",) and d not in index
               and not (d.startswith("adr") and d in adr_index)]
    if missing:
        bad(f"docs/README.md 未索引: {missing}")
    else:
        ok(f"docs 索引完整（{len(docs) - 1} 篇 + adr）")

    adrs = [p for p in tracked("docs/adr/*.md") if os.path.basename(p) != "README.md"]
    if adrs:
        adr_missing = [a for a in adrs if os.path.basename(a) not in adr_index]
        if adr_missing:
            bad(f"docs/adr/README.md 未索引: {adr_missing}")
        else:
            ok(f"ADR 索引完整（{len(adrs)} 篇）")


# --- skills ----------------------------------------------------------------
FM_RE = re.compile(r"^---\n(.*?)\n---\n", re.S)


def check_skills() -> None:
    skills = tracked(".agents/skills/*/SKILL.md")
    if not skills:
        bad(".agents/skills/ 下没有 SKILL.md")
        return
    for s in skills:
        name = os.path.basename(os.path.dirname(s))
        text = open(rel(s), encoding="utf-8").read()
        m = FM_RE.match(text)
        if not m:
            bad(f"{s}: 缺少 YAML frontmatter")
            continue
        fm = m.group(1)
        fname = re.search(r"(?m)^name:\s*(\S+)", fm)
        desc = re.search(r"(?m)^description:\s*(.+)$", fm)
        if not fname or fname.group(1) != name:
            bad(f"{s}: frontmatter name 必须等于目录名 '{name}'")
        elif not desc or len(desc.group(1).strip()) < 30:
            bad(f"{s}: frontmatter description 缺失或过短")
        else:
            ok(f"skill {name}: frontmatter 合法")


# --- hygiene ---------------------------------------------------------------
def check_hygiene() -> None:
    scripts = tracked("scripts/*.sh", "scripts/**/*.sh")
    bad_mode = [p for p in scripts if not os.stat(rel(p)).st_mode & 0o111]
    if bad_mode:
        bad(f"缺少可执行位: {bad_mode}")
    else:
        ok(f"scripts: {len(scripts)} 个脚本均有可执行位")

    forbidden = [p for p in tracked()
                 if p.endswith((".apk", ".aab"))
                 or p.startswith(("out/", "artifacts/"))
                 or "__pycache__" in p]
    if forbidden:
        bad(f"禁止跟踪的文件: {forbidden}")
    else:
        ok("未跟踪 APK / out/ / artifacts/ / __pycache__")

    no_newline = []
    for p in tracked("*.md", "*.sh", "*.py", "*.patch", "*.yml", "Makefile"):
        data = open(rel(p), "rb").read()
        if data and not data.endswith(b"\n"):
            no_newline.append(p)
    if no_newline:
        bad(f"文件缺少结尾换行: {no_newline[:5]}")
    else:
        ok("文本文件均以换行结尾")

    if os.path.exists(rel("keys/lumo-dev.jks")):
        readme = open(rel("keys/README.md"), encoding="utf-8").read()
        if "debug" not in readme.lower() or "SHA-256" not in readme:
            bad("keys/README.md 必须写明 debug-only 与证书指纹")
        else:
            ok("keys: dev key 存在且 README 声明了范围与指纹")
    else:
        bad("缺少 keys/lumo-dev.jks")


def main() -> int:
    print("== 补丁 ==")
    check_patches()
    print("== 文档链接 ==")
    check_links()
    print("== 文档索引 ==")
    check_docs_index()
    print("== Agent skills ==")
    check_skills()
    print("== 卫生 ==")
    check_hygiene()

    print()
    if FAILS:
        print(f"仓库卫生检查失败：{len(FAILS)} 项（通过 {OKS}）")
        return 1
    print(f"仓库卫生检查通过：{OKS} 项")
    return 0


if __name__ == "__main__":
    sys.exit(main())
