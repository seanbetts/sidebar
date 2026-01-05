#!/usr/bin/env python3
"""
Import GoodLinks ck-rules.js into SideBar rule YAML.

Usage:
  python goodlinks-testing/import_ck_rules.py \
    --export-path goodlinks-testing/GoodLinks-Export-2025.json \
    --output backend/skills/web-save/rules/goodlinks-imported.yaml
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Iterable, Optional

import yaml


DEFAULT_RULES_PATH = Path.home() / "Library/Containers/com.ngocluu.goodlinks/Data/Library/Application Support/ck-rules.js"
DEFAULT_EXPORT_PATH = Path(__file__).resolve().parent / "GoodLinks-Export-2025.json"
DEFAULT_OUTPUT_PATH = (
    Path(__file__).resolve().parents[1]
    / "backend"
    / "skills"
    / "web-save"
    / "rules"
    / "goodlinks-imported.yaml"
)
DEFAULT_REPORT_PATH = Path(__file__).resolve().parent / "ck_rules_import_report.json"


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import GoodLinks ck-rules.js into YAML.")
    parser.add_argument("--rules-path", default=str(DEFAULT_RULES_PATH))
    parser.add_argument("--export-path", default=str(DEFAULT_EXPORT_PATH))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH))
    parser.add_argument("--report", default=str(DEFAULT_REPORT_PATH))
    parser.add_argument(
        "--mapping",
        default="auto",
        choices=["auto", "md5_host", "md5_www", "md5_etld1", "md5_https", "md5_http"],
        help="Force host mapping method.",
    )
    return parser.parse_args(argv)


def load_ck_rules(path: Path) -> dict[str, dict]:
    text = path.read_text()
    marker = "globalThis.ckRules"
    if marker not in text:
        raise ValueError("Unable to locate ckRules payload")
    payload = text.split(marker, 1)[1]
    payload = payload.split("=", 1)[-1].strip()
    if payload.endswith(";"):
        payload = payload[:-1]
    payload = payload.strip()
    payload = json.loads(payload)
    return {key: json.loads(value) for key, value in payload.items()}


def normalize_host(url: str) -> str:
    try:
        import urllib.parse as parse
    except ImportError:  # pragma: no cover
        return ""
    host = parse.urlparse(url).hostname or ""
    return host.lower().lstrip("www.")


def etld1_naive(host: str) -> str:
    parts = host.split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else host


def md5(value: str) -> str:
    return hashlib.md5(value.encode("utf-8")).hexdigest()


def resolve_mapping(
    hosts: list[str], rule_keys: set[str], mapping: str
) -> tuple[str, dict[str, str], dict[str, int]]:
    methods = {
        "md5_host": lambda h: md5(h),
        "md5_www": lambda h: md5(f"www.{h}"),
        "md5_etld1": lambda h: md5(etld1_naive(h)),
        "md5_https": lambda h: md5(f"https://{h}"),
        "md5_http": lambda h: md5(f"http://{h}"),
    }
    if mapping != "auto":
        method = methods[mapping]
        hits = {h: method(h) for h in hosts if method(h) in rule_keys}
        counts = {mapping: len(hits)}
        return mapping, hits, counts

    best_name = "md5_host"
    best_hits: dict[str, str] = {}
    counts: dict[str, int] = {}
    for name, fn in methods.items():
        hits = {h: fn(h) for h in hosts if fn(h) in rule_keys}
        counts[name] = len(hits)
        if len(hits) > len(best_hits):
            best_name = name
            best_hits = hits
    return best_name, best_hits, counts


def split_selectors(value: Optional[str | list[str]]) -> list[str]:
    if not value:
        return []
    if isinstance(value, list):
        return [item.strip() for item in value if item and str(item).strip()]
    return [item.strip() for item in value.split(",") if item.strip()]


def build_metadata(payload: dict) -> dict:
    mapping = {"t": "title", "b": "author", "p": "published"}
    meta: dict[str, dict] = {}
    for key, field in mapping.items():
        selector = payload.get(key)
        if not selector:
            continue
        entry: dict[str, str] = {"selector": selector}
        if selector.startswith("meta["):
            entry["attr"] = "content"
        meta[field] = entry
    return meta


def map_actions(actions: list[dict]) -> tuple[list[dict], list[dict]]:
    mapped: list[dict] = []
    unsupported: list[dict] = []
    for action in actions:
        selector = action.get("s")
        if not selector:
            continue
        handled_keys = {"s"}
        if action.get("rc"):
            mapped.append({"op": "remove_children", "selector": selector})
            handled_keys.add("rc")
        if "rt" in action:
            mapped.append({"op": "retag", "selector": selector, "tag": action["rt"]})
            handled_keys.add("rt")
        if "ra" in action:
            mapped.append(
                {"op": "remove_attrs", "selector": selector, "attrs": [action["ra"]]}
            )
            handled_keys.add("ra")
        if "g" in action or "gs" in action:
            mapped.append(
                {
                    "op": "set_attr",
                    "selector": selector,
                    "attr": "class",
                    "value": action.get("g") or action.get("gs"),
                }
            )
            handled_keys.update({"g", "gs"})
        if action.get("rp"):
            mapped.append({"op": "remove_parent", "selector": selector})
            handled_keys.add("rp")
        if action.get("rop"):
            mapped.append({"op": "remove_outer_parent", "selector": selector})
            handled_keys.add("rop")
        if action.get("rtp") and action.get("tp"):
            mapped.append(
                {
                    "op": "remove_to_parent",
                    "selector": selector,
                    "parent": action["tp"],
                }
            )
            handled_keys.update({"rtp", "tp"})
        if "t" in action:
            position = "append"
            if action.get("ts") == 1:
                position = "prepend"
            mapped.append(
                {
                    "op": "move",
                    "selector": selector,
                    "target": action["t"],
                    "position": position,
                }
            )
            handled_keys.update({"t", "ts"})
        elif "tp" in action:
            mapped.append(
                {
                    "op": "move",
                    "selector": selector,
                    "target": action["tp"],
                }
            )
            handled_keys.add("tp")

        unsupported_keys = [key for key in action.keys() if key not in handled_keys]
        if unsupported_keys:
            unsupported.append({"selector": selector, "keys": unsupported_keys})
    return mapped, unsupported


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    rules_path = Path(args.rules_path)
    export_path = Path(args.export_path)
    output_path = Path(args.output)
    report_path = Path(args.report)

    ck_rules = load_ck_rules(rules_path)
    export_data = json.loads(export_path.read_text())
    items = export_data if isinstance(export_data, list) else export_data.get("items") or []
    hosts = [normalize_host(item.get("url", "")) for item in items if isinstance(item, dict)]
    hosts = [host for host in hosts if host]
    top_hosts = [host for host, _ in Counter(hosts).most_common(1000)]

    mapping_method, host_map, mapping_counts = resolve_mapping(
        top_hosts, set(ck_rules.keys()), args.mapping
    )
    reverse_map = {value: key for key, value in host_map.items()}

    rules: list[dict] = []
    unmapped_keys: list[str] = []
    unsupported_actions: list[dict] = []
    rules_with_d = []
    rules_with_ea = []

    for key, payload in ck_rules.items():
        host = reverse_map.get(key)
        if not host:
            unmapped_keys.append(key)
            continue
        rule_id = f"goodlinks-{host.replace('.', '-')}"
        selector_overrides: dict[str, str] = {}
        if payload.get("a"):
            selector_overrides["article"] = payload["a"]
        if payload.get("we"):
            selector_overrides["wrapper"] = payload["we"]

        remove = split_selectors(payload.get("e"))
        include = split_selectors(payload.get("i"))
        metadata = build_metadata(payload.get("m") or {})
        mapped_actions, unsupported = map_actions(payload.get("ac") or [])
        if unsupported:
            unsupported_actions.extend(
                [{"rule_id": rule_id, **entry} for entry in unsupported]
            )
        phase = "pre" if selector_overrides else "post"
        if payload.get("ea"):
            rules_with_ea.append(rule_id)
        if payload.get("d"):
            rules_with_d.append(rule_id)

        rules.append(
            {
                "id": rule_id,
                "phase": phase,
                "priority": 80,
                "trigger": {"host": {"ends_with": host}},
                "selector_overrides": selector_overrides,
                "remove": remove,
                "include": include,
                "actions": mapped_actions,
                "metadata": metadata,
            }
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(yaml.safe_dump(rules, sort_keys=False))

    report = {
        "rules_count": len(ck_rules),
        "mapped_rules": len(rules),
        "mapping_method": mapping_method,
        "mapping_counts": mapping_counts,
        "unmapped_keys": unmapped_keys,
        "unsupported_actions": unsupported_actions,
        "rules_with_ea": rules_with_ea,
        "rules_with_d": rules_with_d,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True))

    print(f"Wrote {output_path}")
    print(f"Wrote {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
