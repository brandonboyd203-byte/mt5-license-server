#!/usr/bin/env python3
import os
import re
import sys

ROOT = "/Users/brandonboyd/.openclaw/workspace"

TARGETS = {
    "bots_full/GoldmineFresh_Gold.mq5": {
        "ScalpBE_Pips": 25.0,
        "BreakEvenPips": 25.0,
        "REV_BEPips": 25.0,
    },
    "bots_full/GoldmineFresh_Gold_VPS.mq5": {
        "ScalpBE_Pips": 25.0,
        "BreakEvenPips": 25.0,
        "REV_BEPips": 25.0,
    },
    "bots_src/GoldmineFresh_Gold.mq5": {
        "ScalpBE_Pips": 25.0,
        "BreakEvenPips": 25.0,
        "REV_BEPips": 25.0,
    },
    "bots_full/GoldmineBlueprint_Gold.mq5": {
        "BreakEvenPips": 25.0,
    },
    "bots_full/GoldmineBlueprint_Gold_VPS.mq5": {
        "BreakEvenPips": 25.0,
    },
}


def set_input_value(text: str, name: str, value: float) -> tuple[str, bool]:
    pattern = re.compile(rf"(input\s+double\s+{re.escape(name)}\s*=\s*)([0-9.]+)", re.IGNORECASE)
    replacement = rf"\g<1>{value:.1f}"
    new_text, n = pattern.subn(replacement, text, count=1)
    return new_text, n > 0 and new_text != text


changed_files = []
missing_files = []

for rel_path, inputs in TARGETS.items():
    path = os.path.join(ROOT, rel_path)
    if not os.path.exists(path):
        missing_files.append(rel_path)
        continue
    with open(path, "r", errors="ignore") as f:
        text = f.read()
    original = text
    for name, value in inputs.items():
        text, _ = set_input_value(text, name, value)
    if text != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        changed_files.append(rel_path)

if missing_files:
    print("missing:", ", ".join(missing_files))

if changed_files:
    print("changed:", ", ".join(changed_files))
else:
    print("no changes")

sys.exit(0)
