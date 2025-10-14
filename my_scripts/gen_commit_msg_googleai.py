#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
使用 Google Generative AI（Gemini）或离线规则生成提交信息摘要。

环境变量
- GEMINI_API_KEY / GOOGLE_API_KEY / GOOGLEAI_API_KEY：Google AI Studio API Key（可选）。

说明
- 提交信息生成时会忽略外部知识库目录（my_docs/project_docs/kernel_reference），
  由 my_scripts/docs_whitelist.json 控制。
"""

from __future__ import annotations

import os
import subprocess
import sys
import json
from pathlib import Path
from typing import Optional, List
import urllib.request
import urllib.error
import ssl


REPO_ROOT = Path(__file__).resolve().parents[1]
CFG_PATH = REPO_ROOT / "my_scripts" / "docs_whitelist.json"


def run(cmd: list[str]) -> str:
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        return out.decode("utf-8", errors="replace")
    except subprocess.CalledProcessError as e:
        return e.output.decode("utf-8", errors="replace")


def _load_doc_excludes() -> List[str]:
    try:
        if CFG_PATH.exists():
            data = json.loads(CFG_PATH.read_text(encoding="utf-8"))
            return [str(x).replace("\\", "/").rstrip("/") for x in data.get("doc_write_exclude", [])]
    except Exception:
        pass
    return []


EX_DOCS = _load_doc_excludes()
EXTRA_EXCLUDED_FILES = [
    # Do not include whitelist changes in commit message generation
    "my_scripts/docs_whitelist.json",
]


def _is_excluded_path(path_rel: str) -> bool:
    rp = path_rel.replace("\\", "/").lstrip("./")
    for e in EX_DOCS:
        if rp == e or rp.startswith(e + "/"):
            return True
    for f in EXTRA_EXCLUDED_FILES:
        if rp == f:
            return True
    return False


def collect_diff_filtered(max_patch_chars: int = 8000) -> tuple[str, str]:
    names_raw = run(["git", "diff", "--staged", "--name-only"]).strip().splitlines()
    names = [n for n in (x.strip() for x in names_raw) if n and not _is_excluded_path(n)]
    if names:
        stat = run(["git", "diff", "--staged", "--name-status", "--", *names]).strip()
        patch = run(["git", "diff", "--staged", "--unified=0", "--", *names]).strip()
    else:
        stat = ""
        patch = ""
    if len(patch) > max_patch_chars:
        patch = patch[: max_patch_chars - 1] + "\n…(truncated)"
    return stat, patch


PROMPT_TMPL = (
    "请阅读以下 Git 变更，生成提交信息：\n"
    "- 第一行不超过 60 字，格式 `type: subject`，type ∈ [feat, fix, docs, chore, refactor, test, perf, build, ci]\n"
    "- 然后列出 1-3 条要点，每条一行，以 `- ` 开头\n\n"
    "文件清单（name-status）：\n{stat}\n\n"
    "差异片段（可能已截断）：\n{patch}\n"
)


def build_prompt(stat: str, patch: str, lang: str) -> str:
    lang = (lang or "zh").lower()
    # 开头给出中文要求，避免模型输出多余说明
    chs_instr = (
        "请直接给出符合规范的中文提交信息，不要添加额外说明。\n"
        "第一行最长 60 字，格式 `type: subject`，type ∈ {feat, fix, docs, chore, refactor, test, perf, build, ci}。\n"
        "然后列出 1-3 条要点，每条以 `- ` 开头。\n\n"
    )
    return chs_instr + PROMPT_TMPL.format(stat=stat, patch=patch)


def _debug(msg: str) -> None:
    if os.environ.get("COMMIT_MSG_DEBUG", "0") == "1":
        try:
            sys.stderr.write(f"[commit-msg] {msg}\n")
        except Exception:
            pass


def _generate_with_gemini_rest(prompt: str) -> Optional[str]:
    api_key = (
        os.environ.get("GEMINI_API_KEY")
        or os.environ.get("GOOGLE_API_KEY")
        or os.environ.get("GOOGLEAI_API_KEY")
    )
    if not api_key:
        _debug("REST fallback: no API key")
        return None
    # REST endpoint
    model = os.environ.get("GEMINI_MODEL", "gemini-1.5-flash")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
    payload = {
        "contents": [
            {"parts": [{"text": prompt}]}
        ]
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        # Allow default SSL context
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            obj = json.loads(raw)
    except urllib.error.HTTPError as e:
        _debug(f"REST HTTPError: {e.code}")
        return None
    except Exception as e:
        _debug(f"REST exception: {e}")
        return None
    # Parse candidates
    try:
        cands = obj.get("candidates") or []
        texts: List[str] = []
        for c in cands:
            content = c.get("content") or {}
            parts = content.get("parts") or []
            for part in parts:
                t = part.get("text")
                if t:
                    texts.append(t)
        text = "\n".join([t for t in texts if t]).strip()
        return text or None
    except Exception as e:
        _debug(f"REST parse exception: {e}")
        return None


def generate_with_gemini(prompt: str) -> Optional[str]:
    api_key = (
        os.environ.get("GEMINI_API_KEY")
        or os.environ.get("GOOGLE_API_KEY")
        or os.environ.get("GOOGLEAI_API_KEY")
    )
    if not api_key:
        _debug("no API key in GEMINI_API_KEY/GOOGLE_API_KEY/GOOGLEAI_API_KEY; try offline fallback")
        return None
    try:
        import google.generativeai as genai  # type: ignore
    except Exception:
        _debug("google-generativeai package not installed; trying REST fallback")
        return _generate_with_gemini_rest(prompt)
    try:
        genai.configure(api_key=api_key)
        model_name = os.environ.get("GEMINI_MODEL", "gemini-1.5-flash")
        model = genai.GenerativeModel(model_name)
        resp = model.generate_content(prompt)
        text = getattr(resp, "text", None)
        if not text and hasattr(resp, "candidates") and resp.candidates:
            parts = []
            for c in resp.candidates:
                try:
                    parts.append(c.content.parts[0].text)
                except Exception:
                    continue
            text = "\n".join([p for p in parts if p])
        if text:
            return text.strip()
        _debug("empty response text from SDK; trying REST fallback")
        return _generate_with_gemini_rest(prompt)
    except Exception as e:
        _debug(f"SDK exception: {e}; trying REST fallback")
        return _generate_with_gemini_rest(prompt)


def _guess_type_from_paths(files: list[str]) -> str:
    if not files:
        return "chore"
    lower = [f.lower() for f in files]
    # 纯文档更改
    doc_exts = (".md", ".rst", ".txt")
    if all(f.endswith(doc_exts) or f.startswith(("docs/", "my_docs/")) or "readme" in f for f in lower):
        return "docs"
    # 测试主导
    if any("test" in f or f.startswith("tests/") for f in lower):
        return "test"
    # 构建/配置
    if any(f.endswith(('.cmake', 'cmakelists.txt', '.yml', '.yaml', '.toml', '.json')) for f in lower):
        return "build"
    # 代码变更
    if any(f.endswith(('.c', '.cc', '.cpp', '.cu', '.cuh', '.h', '.hpp')) for f in lower):
        return "feat"
    if any(f.endswith(('.py', '.ps1', '.sh')) for f in lower):
        return "chore"
    return "chore"


def _top_components(files: list[str], k: int = 3) -> list[str]:
    comps: list[str] = []
    seen: set[str] = set()
    for f in files:
        part = f.split('/', 1)[0]
        if part and part not in seen:
            seen.add(part)
            comps.append(part)
        if len(comps) >= k:
            break
    return comps


def generate_offline(stat: str, patch: str) -> Optional[str]:
    files: list[str] = []
    adds = mods = dels = 0
    for line in (stat or "").splitlines():
        line = line.strip()
        if not line:
            continue
        # format: "M\tpath" or "M path"
        parts = line.split('\t') if '\t' in line else line.split(None, 1)
        if not parts:
            continue
        code = parts[0].strip().upper()
        path = parts[1].strip() if len(parts) > 1 else ''
        if not path:
            continue
        files.append(path.replace('\\', '/'))
        if code.startswith('A'):
            adds += 1
        elif code.startswith('D'):
            dels += 1
        else:
            mods += 1

    # 粗略统计行增删
    plus = minus = 0
    for raw in (patch or "").splitlines():
        if raw.startswith(('diff --git', 'index ', '--- ', '+++ ', '@@')):
            continue
        if raw.startswith('+') and not raw.startswith('+++'):
            plus += 1
        elif raw.startswith('-') and not raw.startswith('---'):
            minus += 1

    ctype = _guess_type_from_paths(files)
    comps = _top_components(files)
    if not files and not (plus or minus):
        return None

    if ctype == 'docs':
        subject = f"更新文档{('（' + '、'.join(comps) + '）') if comps else ''}"
    elif ctype == 'test':
        subject = f"完善测试{('（' + '、'.join(comps) + '）') if comps else ''}"
    elif ctype == 'build':
        subject = f"构建/配置更新{('（' + '、'.join(comps) + '）') if comps else ''}"
    elif ctype == 'feat':
        subject = f"功能/实现更新{('（' + '、'.join(comps) + '）') if comps else ''}"
    else:
        subject = f"杂项更新{('（' + '、'.join(comps) + '）') if comps else ''}"

    bullets: list[str] = []
    bullets.append(f"变更：修改 {mods}，新增 {adds}，删除 {dels}；+{plus}/-{minus} 行")
    if files:
        sample = '、'.join(files[:3]) + (" 等" if len(files) > 3 else "")
        bullets.append(f"涉及：{sample}")

    body = "\n".join([f"{ctype}: {subject}"] + [f"- {b}" for b in bullets])
    return body.strip()


def main() -> int:
    stat, patch = collect_diff_filtered()
    # Always try to generate, even for comment-only patches
    if not stat and not patch:
        # 没有变更：保持兼容返回占位
        print('chore: update\n- 无文件变更（占位）')
        return 0
    lang = os.environ.get("COMMIT_MSG_LANG", "zh").lower()
    prompt = build_prompt(stat, patch, lang)
    text = generate_with_gemini(prompt)
    if not text:
        offline = generate_offline(stat, patch)
        if offline:
            print(offline.strip())
        else:
            print('chore: update\n- 占位提交（未能生成摘要）')
        return 0
    print(text.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())

