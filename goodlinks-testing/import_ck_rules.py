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
DEFAULT_OVERRIDE_PATH = Path(__file__).resolve().parent / "ck_rules_mapping_overrides.json"


def parse_args(argv: Optional[Iterable[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import GoodLinks ck-rules.js into YAML.")
    parser.add_argument("--rules-path", default=str(DEFAULT_RULES_PATH))
    parser.add_argument("--export-path", default=str(DEFAULT_EXPORT_PATH))
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH))
    parser.add_argument("--report", default=str(DEFAULT_REPORT_PATH))
    parser.add_argument("--overrides", default=str(DEFAULT_OVERRIDE_PATH))
    parser.add_argument(
        "--mapping",
        default="auto",
        choices=["auto", "md5_host", "md5_www", "md5_etld1", "md5_https", "md5_http"],
        help="Force host mapping method.",
    )
    parser.add_argument(
        "--enable-etld1",
        action="store_true",
        help="Enable naive eTLD+1 matching (use with caution).",
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


def extract_host_from_selectors(values: Iterable[str]) -> Optional[str]:
    urls = re.findall(r"https?://[^\\s\\\"\\'\\)]+", " ".join(values))
    hosts = {normalize_host(url) for url in urls if normalize_host(url)}
    if len(hosts) == 1:
        return hosts.pop()
    return None


def etld1_naive(host: str) -> str:
    parts = host.split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else host


def md5(value: str) -> str:
    return hashlib.md5(value.encode("utf-8")).hexdigest()


def resolve_mapping(
    hosts: list[str],
    rule_keys: set[str],
    mapping: str,
    *,
    enable_etld1: bool,
) -> tuple[str, dict[str, str], dict[str, int]]:
    methods = {
        "md5_host": lambda h: md5(h),
        "md5_www": lambda h: md5(f"www.{h}"),
        "md5_https": lambda h: md5(f"https://{h}"),
        "md5_http": lambda h: md5(f"http://{h}"),
    }
    if enable_etld1:
        methods["md5_etld1"] = lambda h: md5(etld1_naive(h))
    def variants(host: str) -> list[str]:
        base = host
        with_www = f"www.{host}"
        return [base, with_www]

    if mapping != "auto":
        method = methods[mapping]
        hits: dict[str, str] = {}
        for host in hosts:
            for candidate in variants(host):
                key = method(candidate)
                if key in rule_keys:
                    hits[host] = key
                    break
        counts = {mapping: len(set(hits.values()))}
        return mapping, hits, counts

    best_name = "md5_host"
    best_hits: dict[str, str] = {}
    counts: dict[str, int] = {}
    for name, fn in methods.items():
        hits: dict[str, str] = {}
        for host in hosts:
            for candidate in variants(host):
                key = fn(candidate)
                if key in rule_keys:
                    hits[host] = key
                    break
        counts[name] = len(set(hits.values()))
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


def is_specific_selector(selector: str) -> bool:
    generic = {
        "article",
        "section",
        "aside",
        "mark",
        "figure",
        "figcaption",
        "header",
        "footer",
        "main",
        "nav",
        "p",
        "a",
        "img",
        "svg",
        "cite",
        "time",
        "ul",
        "ol",
        "li",
    }
    if selector in generic:
        return False
    if re.fullmatch(r"h[1-6]", selector):
        return False
    return any(token in selector for token in (".", "#", "[", ">", ":", "^=", "*="))


def collect_signature_selectors(payload: dict) -> list[str]:
    selectors: list[str] = []
    selectors.extend(split_selectors(payload.get("a")))
    selectors.extend(split_selectors(payload.get("we")))
    selectors.extend(split_selectors(payload.get("e")))
    selectors.extend(split_selectors(payload.get("i")))
    for value in (payload.get("m") or {}).values():
        if isinstance(value, str):
            selectors.extend(split_selectors(value))
    for action in payload.get("ac") or []:
        for field in ("s", "t", "tp"):
            if field in action and isinstance(action[field], str):
                selectors.extend(split_selectors(action[field]))
    return [selector for selector in selectors if selector]


def is_strong_selector(selector: str) -> bool:
    strong_tokens = (
        "data-testid",
        "DraftEditor",
        "public-DraftEditor",
        "intercom-interblocks",
        "swiper-",
        "devsite-",
        "sqs-",
        "post-paywall",
        "data-gu-name",
    )
    if any(token in selector for token in strong_tokens):
        return True
    return any(token in selector for token in (".", "#", "[")) and len(selector) > 6


def split_selector_strength(selectors: list[str]) -> tuple[list[str], list[str]]:
    strong: list[str] = []
    weak: list[str] = []
    for selector in selectors:
        if is_strong_selector(selector):
            strong.append(selector)
        else:
            weak.append(selector)
    return strong, weak


def main(argv: Optional[Iterable[str]] = None) -> int:
    args = parse_args(argv)
    rules_path = Path(args.rules_path)
    export_path = Path(args.export_path)
    output_path = Path(args.output)
    report_path = Path(args.report)
    overrides_path = Path(args.overrides)

    ck_rules = load_ck_rules(rules_path)
    export_data = json.loads(export_path.read_text())
    items = export_data if isinstance(export_data, list) else export_data.get("items") or []
    hosts = [normalize_host(item.get("url", "")) for item in items if isinstance(item, dict)]
    hosts = [host for host in hosts if host]
    unique_hosts = sorted(set(hosts))

    mapping_method, host_map, mapping_counts = resolve_mapping(
        unique_hosts,
        set(ck_rules.keys()),
        args.mapping,
        enable_etld1=args.enable_etld1,
    )
    reverse_map = {value: key for key, value in host_map.items()}
    overrides: dict[str, list[str]] = {}
    if overrides_path.exists():
        raw_overrides = json.loads(overrides_path.read_text()) or {}
        for key, value in raw_overrides.items():
            if isinstance(value, list):
                overrides[key] = value
            elif isinstance(value, str):
                overrides[key] = [value]

    rules: list[dict] = []
    dropped_rule_keys: list[str] = []
    inferred_hosts: dict[str, str] = {}
    unsupported_actions: list[dict] = []
    rules_with_d = []
    rules_with_ea = []
    unmapped_rules: list[dict] = []
    signature_rules = 0
    dropped_rules = 0
    host_rule_keys: set[str] = set()
    shape_counts: dict[str, int] = {}

    for key, payload in ck_rules.items():
        base_id = f"goodlinks-{key[:8]}"
        hosts = overrides.get(key)
        shape = "+".join(
            part
            for part, present in {
                "a": bool(payload.get("a")),
                "we": bool(payload.get("we")),
                "e": bool(payload.get("e")),
                "i": bool(payload.get("i")),
                "ac": bool(payload.get("ac")),
                "m": bool(payload.get("m")),
                "ea": bool(payload.get("ea")),
                "d": bool(payload.get("d")),
            }.items()
            if present
        )
        shape_counts[shape] = shape_counts.get(shape, 0) + 1
        if not hosts:
            host = reverse_map.get(key)
            if host:
                hosts = [host]
            else:
                selectors = collect_signature_selectors(payload)
                inferred = extract_host_from_selectors(selectors)
                if inferred:
                    inferred_hosts[key] = inferred
                    hosts = [inferred]
        if not hosts:
            selectors = collect_signature_selectors(payload)
            specific_selectors = [selector for selector in selectors if is_specific_selector(selector)]
            strong, weak = split_selector_strength(specific_selectors)
            selector_overrides: dict[str, str] = {}
            if payload.get("a"):
                selector_overrides["article"] = payload["a"]
            if payload.get("we"):
                selector_overrides["wrapper"] = payload["we"]
            phase = "pre" if selector_overrides else "post"
            if strong:
                signature_rules += 1
                rules.append(
                    {
                        "id": f"goodlinks-signature-{key[:8]}",
                        "phase": phase,
                        "priority": 60,
                        "trigger": {"dom": {"any": strong}},
                        "selector_overrides": selector_overrides,
                        "remove": split_selectors(payload.get("e")),
                        "include": split_selectors(payload.get("i")),
                        "actions": map_actions(payload.get("ac") or [])[0],
                        "metadata": build_metadata(payload.get("m") or {}),
                    }
                )
            elif len(weak) >= 2:
                signature_rules += 1
                rules.append(
                    {
                        "id": f"goodlinks-signature-{key[:8]}",
                        "phase": phase,
                        "priority": 60,
                        "trigger": {"dom": {"all": weak[:2]}},
                        "selector_overrides": selector_overrides,
                        "remove": split_selectors(payload.get("e")),
                        "include": split_selectors(payload.get("i")),
                        "actions": map_actions(payload.get("ac") or [])[0],
                        "metadata": build_metadata(payload.get("m") or {}),
                    }
                )
            else:
                dropped_rules += 1
                dropped_rule_keys.append(key)
                selector_summary = {
                    "a": payload.get("a"),
                    "we": payload.get("we"),
                    "e": payload.get("e"),
                    "i": payload.get("i"),
                    "m": payload.get("m"),
                    "ac": payload.get("ac"),
                }
                unmapped_rules.append({"key": key, "selectors": selector_summary})
            continue
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
                [{"rule_id": base_id, **entry} for entry in unsupported]
            )
        phase = "pre" if selector_overrides else "post"
        if payload.get("ea"):
            rules_with_ea.append(base_id)
        if payload.get("d"):
            rules_with_d.append(base_id)

        for host in hosts:
            if not host:
                continue
            host_id = host.replace(".", "-")
            rule_id = f"goodlinks-{host_id}"
            host_rule_keys.add(key)
            rules.append(
                {
                    "id": f"{rule_id}-{key[:4]}" if len(hosts) > 1 else rule_id,
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
        "host_rules_mapped": len(host_rule_keys),
        "signature_rules_loaded": signature_rules,
        "dropped_rules": dropped_rules,
        "mapping_method": mapping_method,
        "mapping_counts": mapping_counts,
        "inferred_hosts": inferred_hosts,
        "dropped_rule_keys": dropped_rule_keys,
        "unmapped_rules": unmapped_rules,
        "unsupported_actions": unsupported_actions,
        "rules_with_ea": rules_with_ea,
        "rules_with_d": rules_with_d,
        "shape_counts": shape_counts,
    }
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True))

    print(f"Wrote {output_path}")
    print(f"Wrote {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
