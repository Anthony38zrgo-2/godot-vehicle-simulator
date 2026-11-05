"""Parse data assignments without evaluating archive contents as Python/code."""
import re


def parse_value(text):
    text = text.strip()
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1]
    if text.startswith("{") and text.endswith("}"):
        return [parse_value(x) for x in text[1:-1].split(",")]
    if re.fullmatch(r"[-+]?\d+", text):
        return int(text)
    if re.fullmatch(r"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", text):
        return float(text)
    return {"unparsed": text}


def parse_config(data):
    if isinstance(data, bytes):
        data = data.decode("latin1")
    values, issues = {}, []
    # Quoted strings can contain # and semicolons; comments outside quotes cannot.
    clean = re.sub(r'"[^"\r\n]*"|#[^\r\n]*', lambda m: m[0] if m[0].startswith('"') else "", data)
    for match in re.finditer(r"([A-Za-z][A-Za-z0-9_]*)\s*=\s*([^;]+);", clean):
        name, raw = match.groups()
        value = parse_value(raw)
        if name in values:
            issues.append({"field": name, "issue": "duplicate_assignment_last_wins"})
        values[name] = value
        if "unparsed" in str(value):
            issues.append({"field": name, "issue": "unparsed_value", "raw": raw.strip()})
    return {"values": values, "issues": issues}


def vector(config, key, default=None):
    value = config.get(key, default)
    if not isinstance(value, list) or len(value) != 3 or not all(isinstance(v, (float, int)) for v in value):
        raise ValueError(f"{key} must be a three-dimensional numeric vector: {value}")
    return value
