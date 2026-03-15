"""Fallback helpers shared by local web-save parsing flows."""

from __future__ import annotations

import logging

from api.services.web_save_antibot import AntibotDetection, detect_antibot_html

logger = logging.getLogger(__name__)

ANTIBOT_FALLBACK_RULE_ID_TEMPLATE = "antibot-{stage}-challenge"


class LocalParseFallbackError(RuntimeError):
    """Signal that local parsing should hand off to an upstream fallback."""

    def __init__(
        self,
        *,
        fallback: str,
        rule_id: str,
        antibot_detection: AntibotDetection | None = None,
        stage: str | None = None,
    ):
        """Initialize fallback context used by upstream save flows."""
        self.fallback = fallback
        self.rule_id = rule_id
        self.antibot_detection = antibot_detection
        self.stage = stage
        message = f"Local parser requested fallback='{fallback}' via rule '{rule_id}'"
        if stage:
            message += f" stage={stage}"
        if antibot_detection:
            message += (
                f" antibot={antibot_detection.challenge_kind}:"
                f"{antibot_detection.reason}"
            )
        super().__init__(message)


def raise_antibot_fallback_if_needed(html: str, *, stage: str) -> None:
    """Raise a LocalParseFallbackError when anti-bot HTML is detected."""
    detection = detect_antibot_html(html)
    if not detection:
        return

    rule_id = ANTIBOT_FALLBACK_RULE_ID_TEMPLATE.format(stage=stage)
    logger.info(
        "web-save antibot detected stage=%s rule=%s kind=%s reason=%s",
        stage,
        rule_id,
        detection.challenge_kind,
        detection.reason,
    )
    raise LocalParseFallbackError(
        fallback="jina",
        rule_id=rule_id,
        antibot_detection=detection,
        stage=stage,
    )
