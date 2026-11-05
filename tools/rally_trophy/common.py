from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent
REPO = PACKAGE.parents[1]
DEFAULT_SOURCE = Path(r"D:\games\rally-throphy")


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def safe_id(value):
    if not re.fullmatch(r"[a-z][a-z0-9_-]{0,79}", value):
        raise ValueError(f"Unsafe vehicle identifier: {value!r}")
    return value


def within(base, relative):
    base = Path(base).resolve()
    text = str(relative).replace("\\", "/")
    if text.startswith("/") or ":" in text or ".." in text.split("/"):
        raise ValueError(f"Unsafe relative path: {relative}")
    path = (base / text).resolve()
    if not path.is_relative_to(base):
        raise ValueError(f"Path escapes root: {relative}")
    return path


def run(command, log, *, cwd=None, timeout=300, require_marker=None):
    log = Path(log)
    log.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run([str(x) for x in command], input="\n", text=True,
                                encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or b""
        log.write_bytes(partial if isinstance(partial, bytes) else partial.encode("utf-8"))
        raise RuntimeError(f"Process timed out after {timeout}s: {log}") from exc
    log.write_text(result.stdout, encoding="utf-8")
    errors = re.search(r"(?m)^\s*(?:SCRIPT ERROR:|ERROR:|Traceback \(most recent call last\):)|Parse Error", result.stdout)
    if result.returncode or errors or (require_marker and require_marker not in result.stdout):
        raise RuntimeError(f"Process failed or emitted errors (exit {result.returncode}): {log}")
    return result.stdout


def code_hash():
    digest = hashlib.sha256()
    for path in sorted(PACKAGE.rglob("*")):
        if path.is_file() and path.suffix in {".py", ".gd", ".json", ".tscn"} and path.relative_to(PACKAGE).parts[0] not in {"recipes", "data", "tests", "__pycache__"}:
            digest.update(path.relative_to(PACKAGE).as_posix().encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()
