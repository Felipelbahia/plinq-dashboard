#!/usr/bin/env python3
"""
sync_rules.py - Bidirectional Multi-AI Interoperability & Parity Checker
Ensures that all rule entrypoints for any AI assistant (Google Antigravity, Claude Code, Cursor, Qwen, OpenRouter, etc.)
remain 100% synchronized with the most recently updated Source of Truth.
"""

import sys
from pathlib import Path

def normalize(text: str) -> str:
    return (
        text.replace("GEMINI.md", "RULES_FILE")
            .replace("CLAUDE.md", "RULES_FILE")
            .replace("AGENTS.md", "RULES_FILE")
            .replace(".cursorrules", "RULES_FILE")
    )

def main():
    root_dir = Path.cwd()
    agent_rules_dir = root_dir / ".agent" / "rules"
    claude_dir = root_dir / ".claude"

    # All possible rule locations
    all_rule_paths = [
        agent_rules_dir / "GEMINI.md",
        agent_rules_dir / "CLAUDE.md",
        agent_rules_dir / "AGENTS.md",
        root_dir / "AGENTS.md",
        root_dir / "CLAUDE.md",
        root_dir / "GEMINI.md",
        root_dir / ".cursorrules",
    ]
    if claude_dir.exists():
        all_rule_paths.append(claude_dir / "CLAUDE.md")

    # Filter to existing files
    existing_files = [p for p in all_rule_paths if p.exists()]

    if not existing_files:
        print("❌ Error: No rules files found to synchronize.")
        sys.exit(1)

    # Find the most recently modified file (newest timestamp)
    newest_file = max(existing_files, key=lambda p: p.stat().st_mtime)
    source_text = newest_file.read_text(encoding="utf-8")
    norm_source = normalize(source_text)

    print(f"🔍 Source of Truth (Most Recent): {newest_file.relative_to(root_dir)}")

    updated_count = 0
    for target in all_rule_paths:
        target.parent.mkdir(parents=True, exist_ok=True)
        need_update = False
        if not target.exists():
            need_update = True
        else:
            target_text = target.read_text(encoding="utf-8")
            if normalize(target_text) != norm_source:
                need_update = True

        if need_update:
            header_name = target.name
            content = (
                source_text
                .replace("# GEMINI.md", f"# {header_name}")
                .replace("# CLAUDE.md", f"# {header_name}")
                .replace("# AGENTS.md", f"# {header_name}")
                .replace("# .cursorrules", f"# {header_name}")
            )
            target.write_text(content, encoding="utf-8")
            print(f"✅ Synchronized: {target.relative_to(root_dir)}")
            updated_count += 1

    if updated_count == 0:
        print("✅ Multi-AI Bidirectional Parity Check Passed: All rule files are 100% synchronized!")

if __name__ == "__main__":
    main()
