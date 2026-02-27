"""Substack-specific helper functions for local web-save parsing."""

from __future__ import annotations

from urllib.parse import urlparse

from api.services.web_save_rules import Rule, RuleEngine


def is_substack_host(host: str) -> bool:
    """Return True when a host belongs to substack.com."""
    normalized = host.lower().strip(".")
    return normalized == "substack.com" or normalized.endswith(".substack.com")


def contains_substack_markers(*fragments: str | None) -> bool:
    """Return True when HTML/markdown fragments contain Substack-specific markers."""
    markers = (
        "substackcdn.com/image/fetch/",
        "substack-post-media.s3.amazonaws.com/public/images/",
        "substackassets.com",
        'name="substack:',
        'property="substack:',
        'data-component-name="image2todom"',
        'data-component-name="imagegallery"',
        'class="available-content"',
        'class="post-content"',
    )
    for fragment in fragments:
        if not fragment:
            continue
        lowered = fragment.lower()
        if any(marker in lowered for marker in markers):
            return True
    return False


def should_apply_substack_cleanup(
    *,
    final_url: str,
    raw_html: str,
    article_html: str,
    markdown: str,
) -> bool:
    """Return True when Substack markdown cleanup should be applied."""
    parsed = urlparse(final_url)
    if is_substack_host(parsed.netloc) or contains_substack_markers(
        raw_html, article_html
    ):
        return True
    return "/p/" in parsed.path and contains_substack_markers(markdown)


def is_substack_host_rule(rule: Rule) -> bool:
    """Return True when a rule is explicitly keyed to substack.com host matching."""
    host_trigger = (rule.trigger or {}).get("host") or {}
    for key in ("equals", "equals_www", "ends_with", "etld_plus_one"):
        value = host_trigger.get(key)
        if isinstance(value, str) and is_substack_host(value):
            return True
    return False


def merge_rules(base_rules: list[Rule], extra_rules: list[Rule]) -> list[Rule]:
    """Merge rule lists by id while preserving priority ordering from inputs."""
    seen: set[str] = set()
    merged: list[Rule] = []
    for rule in base_rules + extra_rules:
        if rule.id in seen:
            continue
        merged.append(rule)
        seen.add(rule.id)
    return merged


def match_substack_host_rules(
    engine: RuleEngine,
    html: str,
    *,
    phase: str,
) -> list[Rule]:
    """Match Substack host rules for a phase using a synthetic Substack URL."""
    matched = engine.match_rules("https://substack.com/p/synthetic", html, phase=phase)
    return [rule for rule in matched if is_substack_host_rule(rule)]
