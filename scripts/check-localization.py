#!/usr/bin/env python3
"""Localization check: Localization/<lang>.lproj tables are consistent with the code and with each other.

    scripts/check-localization.py          check; exit code 0 — all good
    scripts/check-localization.py --keys   print the keys found in the code

A translation key is a Russian string from the code: a Cyrillic literal in loc(...) (JugglerCore, Localizer.swift:
translates into the currently selected language). Interpolations \\(...) are matched against %@, %lld, %d regardless
of type: check the specifier type (Int → %lld, Int32 → %d, everything else → %@) yourself.

A Cyrillic literal in String(localized:) or directly in SwiftUI (Text, Button, Toggle, Section, Picker,
LabeledContent, TextField, Label, .help, .navigationTitle, .accessibilityLabel) is an error: such strings
take the launch language and don't switch without a relaunch. Wrap the literal in loc(...).

Checked:
- each Localizable.strings has exactly the keys from the code (plus "%@, %@" from the summary);
- each translation has the same specifiers as its key (positional %1$@ are allowed);
- Localizable.stringsdict has summary.tasks, summary.done, clearAll.confirm and clearDone.confirm, InfoPlist.strings has
  NSAppleEventsUsageDescription;
- CFBundleLocalizations in scripts/Info.plist matches the set of .lproj folders.
"""
import glob
import json
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CYRILLIC = re.compile("[А-Яа-яЁё]")
CALL = re.compile(r'\bloc\(\s*"')
LEGACY = re.compile(
    r'(String\(localized: |\b(?:Text|Button|Toggle|Section|Picker|LabeledContent|TextField|Label)\(|'
    r'\.help\(|\.navigationTitle\(|\.accessibilityLabel\()\s*"')
SPEC = re.compile(r"%(?:\d+\$)?(?:lld|d|@)")
EXTRA_KEYS = {"%@, %@"}
PLURAL_KEYS = {"summary.tasks", "summary.done", "clearAll.confirm", "clearDone.confirm"}


def single_literal(src, i):
    """Body of a "..." literal starting at quote position i; nested literals inside \\(...) are skipped."""
    j, depth = i + 1, 0
    while True:
        c = src[j]
        if c == "\\" and src[j + 1] == "(":
            depth += 1
            j += 2
            continue
        if depth and c == "(":
            depth += 1
        elif depth and c == ")":
            depth -= 1
        elif depth and c == '"':
            k = j + 1
            while src[k] != '"':
                k += 2 if src[k] == "\\" else 1
            j = k + 1
            continue
        elif not depth and c == "\\":
            j += 2
            continue
        elif not depth and c == '"':
            return src[i + 1:j]
        j += 1


def multi_literal(src, i):
    """Body of a \"\"\"...\"\"\" literal: indentation from the closing quotes, a trailing "\\" joins lines."""
    raw = src[i + 3:src.index('"""', i + 3)]
    lines = raw.split("\n")[1:]
    indent = len(lines[-1])
    text = ""
    for line in lines[:-1]:
        line = line[indent:]
        text += line[:-1] if line.endswith("\\") and not line.endswith("\\\\") else line + "\n"
    return text[:-1] if text.endswith("\n") else text


def normalize(body):
    """\\(...) → ◊, Swift escapes → characters."""
    out, i = "", 0
    while i < len(body):
        if body.startswith("\\(", i):
            depth, j = 1, i + 2
            while depth:
                depth += {"(": 1, ")": -1}.get(body[j], 0)
                j += 1
            out += "◊"
            i = j
        elif body[i] == "\\" and i + 1 < len(body):
            out += {"n": "\n", '"': '"', "\\": "\\"}.get(body[i + 1], body[i:i + 2])
            i += 2
        else:
            out += body[i]
            i += 1
    return out


def literals(pattern):
    """Cyrillic literals right after pattern: {key: "file:line"}."""
    keys = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "Sources/Juggler/**/*.swift"), recursive=True)
                       + glob.glob(os.path.join(ROOT, "Sources/JugglerCore/**/*.swift"), recursive=True)):
        src = open(path, encoding="utf-8").read()
        for m in pattern.finditer(src):
            i = m.end() - 1
            body = multi_literal(src, i) if src.startswith('"""', i) else single_literal(src, i)
            key = normalize(body)
            if CYRILLIC.search(key):
                keys.setdefault(key, f"{os.path.relpath(path, ROOT)}:{src[:i].count(chr(10)) + 1}")
    return keys


def code_keys():
    return literals(CALL)


def load_strings(path):
    out = subprocess.run(["plutil", "-convert", "json", "-o", "-", path], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


def specs(s):
    return sorted(re.sub(r"\d+\$", "", x) for x in SPEC.findall(s))


def main():
    found = code_keys()
    if "--keys" in sys.argv:
        for key, where in found.items():
            print(f"{where}\t{json.dumps(key, ensure_ascii=False)}")
        return 0
    expected = set(found) | {SPEC.sub("◊", k) for k in EXTRA_KEYS}
    problems = [f"{where}: «{key}» не в loc(...) — не переключится без перезапуска"
                for key, where in literals(LEGACY).items()]
    lprojs = sorted(glob.glob(os.path.join(ROOT, "Localization/*.lproj")))
    languages = [os.path.basename(p)[:-len(".lproj")] for p in lprojs]
    for lproj, lang in zip(lprojs, languages):
        table = load_strings(os.path.join(lproj, "Localizable.strings"))
        have = {SPEC.sub("◊", k): k for k in table}
        for key in sorted(expected - set(have)):
            problems.append(f"{lang}: нет перевода «{key}» ({found.get(key, 'сводка')})")
        for key in sorted(set(have) - expected):
            problems.append(f"{lang}: лишний ключ «{have[key]}»")
        for key, value in table.items():
            if specs(key) != specs(value):
                problems.append(f"{lang}: спецификаторы не совпадают: «{key}» → «{value}»")
        plurals = load_strings(os.path.join(lproj, "Localizable.stringsdict"))
        for key in sorted(PLURAL_KEYS - set(plurals)):
            problems.append(f"{lang}: нет {key} в Localizable.stringsdict")
        info = load_strings(os.path.join(lproj, "InfoPlist.strings"))
        if not info.get("NSAppleEventsUsageDescription"):
            problems.append(f"{lang}: нет NSAppleEventsUsageDescription в InfoPlist.strings")
    with open(os.path.join(ROOT, "scripts/Info.plist"), "rb") as f:
        declared = plistlib.load(f).get("CFBundleLocalizations", [])
    if sorted(declared) != languages:
        problems.append(f"CFBundleLocalizations {sorted(declared)} ≠ папки Localization {languages}")
    for p in problems:
        print(p, file=sys.stderr)
    print(f"Локализация: {len(languages)} языков, {len(expected)} ключей, проблем: {len(problems)}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
