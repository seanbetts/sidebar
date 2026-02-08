"""OpenAI-specific markdown cleanup helpers for web-save parsing."""

from __future__ import annotations

import re


def cleanup_openai_markdown(markdown: str) -> str:
    """Remove OpenAI credits/team blocks from markdown."""
    if not markdown:
        return markdown

    link_text_cleanup = re.compile(r"\(opens in a new window\)", re.IGNORECASE)
    labels = {
        "research",
        "product",
        "contributors",
        "leadership",
        "special thanks",
        "safety, integrity, product policy, i2, user ops",
        "legal",
        "communications",
        "marketing, design, & creative",
        "global affairs",
        "strategic finance",
        "api",
    }
    output: list[str] = []
    skipping = False
    footer_mode = False
    kept_footer_meta = 0

    for line in markdown.splitlines():
        stripped = line.strip()
        lowered = stripped.lower()

        if footer_mode:
            if kept_footer_meta < 2 and (
                lowered.startswith("built by openai")
                or lowered.startswith("published ")
            ):
                output.append(stripped)
                kept_footer_meta += 1
            continue

        if stripped in {"Loading…", "Loading...", "Share"}:
            continue

        if stripped.startswith("[Research]") and "openai.com" in stripped:
            continue
        if stripped.startswith("[") and "](" in stripped:
            matches = re.findall(r"\[([^\]]+)\]\(([^)]+)\)", stripped)
            if len(matches) >= 2:
                labels = {label.strip().lower() for label, _ in matches}
                hrefs = [href for _, href in matches]
                if labels.issubset({"research", "product", "release"}) and all(
                    "openai.com" in href for href in hrefs
                ):
                    continue

        if stripped.startswith("## "):
            if lowered in {"## author", "## keep reading"}:
                footer_mode = True
                continue
            if lowered == "## sora 2":
                footer_mode = True
                continue

        if not skipping:
            for label in labels:
                if (lowered == label or lowered.startswith(label)) and (
                    len(stripped) > len(label) + 2
                    or "," in stripped
                    or lowered == label
                ):
                    skipping = True
                    break
            if skipping:
                continue

        if skipping:
            if lowered.startswith("built by openai") or lowered.startswith(
                "published "
            ):
                skipping = False
                output.append(line)
            continue

        if link_text_cleanup.search(stripped):
            output.append(link_text_cleanup.sub("", stripped).strip())
            continue

        output.append(line)

    return "\n".join(output).strip()
