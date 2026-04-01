#!/usr/bin/env python3
# Semantics:
# - Hanya mengganti widget SnackBar(…), BUKAN substring "SnackBar(" di dalam showSnackBar(.
# - Hanya jika content: [const] Text(…) lalu backgroundColor: Colors.red|green|orange (bukan .shade800).
# - Setelah edit, jalankan: dart format & flutter analyze pada file terdampak.
"""One-pass: SnackBar(content: Text(...), backgroundColor: Colors.red|green|orange) -> TrakaSnackBar.*"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "lib"


def matching_paren(s: str, open_idx: int) -> int:
    assert s[open_idx] == "("
    depth = 0
    for j in range(open_idx, len(s)):
        if s[j] == "(":
            depth += 1
        elif s[j] == ")":
            depth -= 1
            if depth == 0:
                return j
    return -1


def extract_text_call(s: str, start: int) -> tuple[str, int] | None:
    if not s.startswith("Text", start):
        return None
    lp = s.index("(", start)
    rp = matching_paren(s, lp)
    if rp < 0:
        return None
    return s[start : rp + 1], rp + 1


def extract_content_text_expr(s: str, inner_start: int) -> tuple[str, int] | None:
    """content: [const] Text(...)"""
    ws = inner_start
    while ws < len(s) and s[ws].isspace():
        ws += 1
    prefix = ""
    if s.startswith("const ", ws):
        prefix = "const "
        ws += len("const ")
        while ws < len(s) and s[ws].isspace():
            ws += 1
    got = extract_text_call(s, ws)
    if got is None:
        return None
    text_expr, end = got
    return prefix + text_expr, end


def traka_import_line(path: Path) -> str:
    rel = path.relative_to(ROOT)
    depth = len(rel.parts) - 1
    prefix = "../" * depth
    return f"import '{prefix}theme/traka_snackbar.dart';\n"


def ensure_import(src: str, path: Path) -> str:
    if "traka_snackbar.dart" in src:
        return src
    lines = src.splitlines(keepends=True)
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith("import "):
            insert_at = i + 1
    lines.insert(insert_at, traka_import_line(path))
    return "".join(lines)


def _next_snackbar_widget(src: str, start: int) -> int:
    """Index of SnackBar( widget — bukan substring di dalam showSnackBar(."""
    while True:
        j = src.find("SnackBar(", start)
        if j < 0:
            return -1
        if j >= 4 and src[j - 4 : j] == "show":
            start = j + 1
            continue
        return j


def replace_snackbar_widgets(src: str) -> str:
    """SnackBar dengan content: [const] Text(...) dan backgroundColor Colors.*."""
    out = []
    i = 0
    while i < len(src):
        j = _next_snackbar_widget(src, i)
        if j < 0:
            out.append(src[i:])
            break
        out.append(src[i:j])
        open_paren = j + len("SnackBar")
        rp = matching_paren(src, open_paren)
        if rp < 0:
            out.append(src[j : j + 9])
            i = j + 9
            continue
        block = src[j : rp + 1]
        m = re.match(r"SnackBar\(\s*content:\s*", block, re.DOTALL)
        if not m:
            out.append(block)
            i = rp + 1
            continue
        inner_start = j + len(m.group(0))
        got = extract_content_text_expr(src, inner_start)
        if got is None:
            out.append(block)
            i = rp + 1
            continue
        text_expr, after_text = got
        rest = src[after_text:rp].strip()
        rm = re.match(
            r"^,\s*backgroundColor:\s*Colors\.(red|green|orange)\s*,?\s*(.*)$",
            rest,
            re.DOTALL,
        )
        if not rm:
            out.append(block)
            i = rp + 1
            continue
        kind = rm.group(1)
        trailing = rm.group(2).strip().rstrip(",")
        trailing = re.sub(
            r"textColor:\s*Colors\.white\s*,?\s*",
            "",
            trailing,
        ).strip().rstrip(",")
        method = {"red": "error", "green": "success", "orange": "warning"}[kind]
        if trailing:
            out.append(
                f"TrakaSnackBar.{method}(context, {text_expr}, {trailing})"
            )
        else:
            out.append(f"TrakaSnackBar.{method}(context, {text_expr})")
        i = rp + 1
    return "".join(out)


def process_file(path: Path) -> bool:
    raw = path.read_text(encoding="utf-8")
    if "SnackBar(" not in raw or "backgroundColor: Colors." not in raw:
        return False
    new = replace_snackbar_widgets(raw)
    if new == raw:
        return False
    new = ensure_import(new, path)
    path.write_text(new, encoding="utf-8")
    return True


def main() -> None:
    n = 0
    for path in sorted(ROOT.rglob("*.dart")):
        if process_file(path):
            print(path.relative_to(ROOT))
            n += 1
    print(f"Updated {n} files (SnackBar -> TrakaSnackBar).")


if __name__ == "__main__":
    main()
