"""Skills = step-by-step procedures (server/skills/<name>/SKILL.md) for multi-step jobs such as building a 3D
culvert. Exposed as MCP prompts (/name in clients that support prompts) and through list_skills / get_skill,
so every AI client can use them."""
from __future__ import annotations

import os
import re

from .drawing import UserError
from .tools import tool

SKILLS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "skills")
# the user's own skills: outside the program folder, so updates never touch them
USER_DIR = os.path.join(os.path.expanduser("~"), "Steve-CAD-AI", "skills")


def load() -> dict[str, dict]:
    out = {}
    dirs = [os.path.join(b, n) for b in (USER_DIR, SKILLS_DIR) if os.path.isdir(b) for n in sorted(os.listdir(b))]
    for path in dirs:   # built-in ones last: a user skill cannot replace them
        name, f = os.path.basename(path), os.path.join(path, "SKILL.md")
        if not os.path.isfile(f):
            continue
        text = open(f, encoding="utf-8-sig").read()
        meta = {"name": name, "description": ""}
        m = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.S)
        if m:
            for line in m.group(1).splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    meta[k.strip()] = v.strip()
            text = text[m.end():]
        meta["body"] = text.strip()
        out[meta["name"]] = meta
    return out


def register_prompts(mcp):
    for name, sk in load().items():
        body = sk["body"]

        def make(body=body):
            def prompt(yeu_cau: str = "") -> str:
                return body + ("\n\n## Yêu cầu của người dùng\n" + yeu_cau if yeu_cau else "")
            return prompt
        mcp.prompt(name=name.replace("-", "_"), description=sk["description"])(make())


@tool()
def list_skills() -> list[dict]:
    """Ready-made procedures for multi-step jobs (e.g. cong-3d: build a 3D culvert from DWG/PDF drawings).
    Call get_skill(name) and follow it when the user's request matches."""
    return [{"name": k, "description": v["description"]} for k, v in load().items()]


@tool()
def get_skill(name: str) -> str:
    """Full step-by-step procedure of a skill (see list_skills). Follow it exactly."""
    sk = load().get(name) or load().get(name.replace("_", "-"))
    if not sk:
        raise UserError(f"Không có skill '{name}'. Xem list_skills.")
    return sk["body"]


@tool("destructive")
def save_skill(name: str, description: str, body: str, overwrite: bool = False) -> dict:
    """Save a skill written with the user (see skill tao-skill) to Steve-CAD-AI\\skills. Show the full text and get their consent
    first. name: lowercase ASCII with dashes; body: Markdown steps. Built-in skills cannot be replaced."""
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name) or len(name) > 40:
        raise UserError("Tên skill chỉ gồm chữ thường không dấu, số và dấu -, tối đa 40 ký tự. Ví dụ: ve-coc-khoan-nhoi.")
    if os.path.isdir(os.path.join(SKILLS_DIR, name)):
        raise UserError(f"'{name}' là skill có sẵn. Chọn tên khác.")
    desc = re.sub(r"\s+", " ", description).strip()
    if len(desc) < 10 or len(body.strip()) < 50:
        raise UserError("Cần mô tả (từ 10 ký tự) và nội dung các bước (từ 50 ký tự).")
    if len(body) > 60000:
        raise UserError("Nội dung quá dài (tối đa 60.000 ký tự).")
    text = f"---\nname: {name}\ndescription: {desc[:300]}\n---\n\n{body.strip()}\n"
    p = os.path.join(USER_DIR, name, "SKILL.md")
    if os.path.exists(p):
        if not overwrite:
            raise UserError(f"Đã có skill '{name}'. Hỏi người dùng rồi dùng overwrite=True.")
        os.replace(p, p + ".bak")
    # second copy: native Claude Code skill of the workspace (/name)
    for f in (p, os.path.join(os.path.dirname(USER_DIR), ".claude", "skills", name, "SKILL.md")):
        os.makedirs(os.path.dirname(f), exist_ok=True)
        with open(f, "w", encoding="utf-8", newline="\n") as h:
            h.write(text)
    return {"ok": True, "path": p, "note": "Dùng được từ phiên chat mới (nút + hoặc /" + name + ")."}
