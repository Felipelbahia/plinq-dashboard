#!/usr/bin/env python3
"""
sync_rules.py - keeps the project's rule files identical.
Usage: python3 .agent/scripts/sync_rules.py [--check | --clean-legacy]
  (no flag)       copy the most recently edited rule file to the others
  --check         read-only, exit 1 if out of parity
  --clean-legacy  offer to delete the old GEMINI.md and .agent/rules/ copies (asks first)

Standard: CLAUDE.md (Claude Code) and AGENTS.md (Antigravity and other tools) at the project root, identical.
.cursorrules and .claude/CLAUDE.md follow the same text only when they already exist; they are never created.
GEMINI.md and .agent/rules/ are legacy: never written, never used as the source, removed only after a yes.
"""

import sys
from pathlib import Path

STANDARD = ["CLAUDE.md", "AGENTS.md"]
OPTIONAL = [".cursorrules", ".claude/CLAUDE.md"]  # Claude Code loads ./CLAUDE.md and ./.claude/CLAUDE.md both
LEGACY = ["GEMINI.md", ".agent/rules/CLAUDE.md", ".agent/rules/GEMINI.md", ".agent/rules/AGENTS.md"]
NAMES = ("GEMINI.md", "CLAUDE.md", "AGENTS.md", ".cursorrules")


def normalize(text: str) -> str:
    for name in NAMES:
        text = text.replace(name, "RULES_FILE")
    return text


def retitle(text: str, name: str) -> str:
    for old in NAMES:
        text = text.replace(f"# {old}", f"# {name}")
    return text


def existing(root: Path, names: list[str]) -> list[Path]:
    return [root / n for n in names if (root / n).is_file()]


def warn_legacy(root: Path) -> None:
    legacy = existing(root, LEGACY)
    if legacy:
        print("⚠️  Legacy rule files (no longer synced):")
        for p in legacy:
            print(f"   - {p.relative_to(root)}")
        print("   Remove them (asks first): python3 .agent/scripts/sync_rules.py --clean-legacy")


def clean_legacy(root: Path, source_text: str) -> None:
    legacy = existing(root, LEGACY)
    if not legacy:
        print("✅ No legacy rule files.")
        return
    norm_source = normalize(source_text)
    same = [p for p in legacy if normalize(p.read_text(encoding="utf-8")) == norm_source]
    for p in legacy:
        status = "identical to the current rules" if p in same else "differs from the current rules: kept, review it by hand"
        print(f"   - {p.relative_to(root)}: {status}")
    if not same:
        return
    try:
        answer = input(f"Delete the {len(same)} identical legacy file(s)? [s/N] ").strip().lower()
    except EOFError:
        answer = ""
    if answer not in ("s", "sim", "y", "yes"):
        print("Nothing deleted.")
        return
    for p in same:
        p.unlink()
        print(f"🗑️  Deleted: {p.relative_to(root)}")
    try:
        (root / ".agent" / "rules").rmdir()  # only succeeds when empty
    except OSError:
        pass


def main():
    root = Path.cwd()
    args = sys.argv[1:]
    sources = existing(root, STANDARD + OPTIONAL)
    all_targets = [root / n for n in STANDARD] + existing(root, OPTIONAL)

    if not sources:
        if "--check" in args or "--clean-legacy" in args:
            # Rule files are git-ignored in 0 Padrões, so a fresh clone has none: nothing to compare.
            print("✅ Parity OK (no rule files in this checkout)")
            return
        print("❌ Error: No rules files found to synchronize.")
        sys.exit(1)

    newest = max(sources, key=lambda p: p.stat().st_mtime)
    source_text = newest.read_text(encoding="utf-8")
    norm_source = normalize(source_text)

    if "--clean-legacy" in args:
        clean_legacy(root, source_text)
        return

    if "--check" in args:
        diverged = [p for p in sources if normalize(p.read_text(encoding="utf-8")) != norm_source]
        if diverged:
            print(f"❌ Rule files out of parity with {newest.relative_to(root)}:")
            for p in diverged:
                print(f"   - {p.relative_to(root)}")
            print("   Fix: python3 .agent/scripts/sync_rules.py")
            sys.exit(1)
        print(f"✅ Parity OK ({len(sources)} rule files)")
        warn_legacy(root)
        return

    print(f"🔍 Source of Truth (Most Recent): {newest.relative_to(root)}")
    updated = 0
    for target in all_targets:
        if target.exists() and normalize(target.read_text(encoding="utf-8")) == norm_source:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(retitle(source_text, target.name), encoding="utf-8")
        print(f"✅ Synchronized: {target.relative_to(root)}")
        updated += 1
    if updated == 0:
        print("✅ Parity Check Passed: all rule files are 100% synchronized!")
    warn_legacy(root)


if __name__ == "__main__":
    main()
