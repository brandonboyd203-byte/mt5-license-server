#!/usr/bin/env python3
import os
import re
import sys

ROOT = "/Users/brandonboyd/.openclaw/workspace"

TARGET_INPUTS = {
    "ScalpBE_Pips": 25.0,
    "BreakEvenPips": 25.0,
    "BreakEvenPips_Silver": 25.0,
    "REV_BEPips": 25.0,
    "OppositeTradeTP_Pips": 10.0,
    "OppositeTradeSL_Pips": 10.0,
}


def set_input_value(text: str, name: str, value: float) -> tuple[str, bool]:
    pattern = re.compile(rf"(input\s+double\s+{re.escape(name)}\s*=\s*)([0-9.]+)", re.IGNORECASE)
    replacement = rf"\g<1>{value:.1f}"
    new_text, n = pattern.subn(replacement, text, count=1)
    return new_text, n > 0 and new_text != text


changed_files = []
missing_files = []

paths = []
for base in ("bots_full", "bots_src"):
    base_path = os.path.join(ROOT, base)
    if not os.path.isdir(base_path):
        continue
    for name in os.listdir(base_path):
        if name.endswith(".mq5"):
            paths.append(os.path.join(base, name))

for rel_path in sorted(set(paths)):
    path = os.path.join(ROOT, rel_path)
    if not os.path.exists(path):
        missing_files.append(rel_path)
        continue
    with open(path, "r", errors="ignore") as f:
        text = f.read()
    original = text
    for name, value in TARGET_INPUTS.items():
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
