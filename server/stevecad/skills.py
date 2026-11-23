"""Skills = step-by-step procedures (server/skills/<name>/SKILL.md) for multi-step jobs such as building a 3D
culvert. Exposed as MCP prompts (/name in clients that support prompts) and through list_skills / get_skill,
so every AI client can use them."""
from __future__ import annotations

import os
import re

from .drawing import UserError
from .tools import tool

SKILLS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "skills")


def load() -> dict[str, dict]:
    out = {}
    if not os.path.isdir(SKILLS_DIR):
        return out
    for name in sorted(os.listdir(SKILLS_DIR)):
        f = os.path.join(SKILLS_DIR, name, "SKILL.md")
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
