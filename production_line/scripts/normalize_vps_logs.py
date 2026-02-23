#!/usr/bin/env python3
import os, sys, glob, codecs

def is_utf16(path):
    with open(path, 'rb') as f:
        sig = f.read(2)
    return sig in (b'\xff\xfe', b'\xfe\xff')

def normalize_file(path, out_dir):
    if not is_utf16(path):
        return None
    with open(path, 'rb') as f:
        raw = f.read()
    try:
        text = raw.decode('utf-16')
    except Exception:
        try:
            text = raw.decode('utf-16-le')
        except Exception:
            return None
    rel = os.path.relpath(path, start=ROOT)
    out_path = os.path.join(out_dir, rel)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(text)
    return out_path

ROOT = sys.argv[1] if len(sys.argv) > 1 else 'production_line/run_logs/latest'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'production_line/run_logs/latest_utf8'

files = [p for p in glob.glob(os.path.join(ROOT, '**', '*.log'), recursive=True)]
converted = 0
for p in files:
    out = normalize_file(p, OUT)
    if out:
        converted += 1

print(f"converted {converted} files to {OUT}")
