"""Simple heuristics to detect Cloudflare or generic anti-bot HTML before rendering."""

from collections.abc import Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class AntibotDetection:
    """Represents a normalized anti-bot detection result."""

    challenge_kind: str
    reason: str


@dataclass(frozen=True)
class Marker:
    """Search marker used to classify challenge pages."""

    kind: str
    description: str
    phrase: str
    is_title: bool = False


_CLOUDFLARE_TITLE_MARKER = Marker(
    kind="cloudflare",
    description="title contains 'Just a moment...'",
    phrase="just a moment",
    is_title=True,
)

_CLOUDFLARE_BODY_MARKERS: tuple[Marker, ...] = (
    Marker(
        kind="cloudflare",
        description="body mentions 'Checking your browser before accessing'",
        phrase="checking your browser before accessing",
    ),
    Marker(
        kind="cloudflare",
        description="page contains cf-browser-verification marker",
        phrase="cf-browser-verification",
    ),
    Marker(
        kind="cloudflare",
        description="page contains cf-error-code marker",
        phrase="cf-error-code",
    ),
)

_GENERIC_MARKERS: tuple[Marker, ...] = (
    Marker(
        kind="generic",
        description="page includes a 'challenge-form' element",
        phrase="challenge-form",
    ),
    Marker(
        kind="generic",
        description="page tells the user to enable cookies",
        phrase="enable cookies",
    ),
    Marker(
        kind="generic",
        description="page warns to wait while verifying",
        phrase="please wait while we verify",
    ),
    Marker(
        kind="generic",
        description="page references DataDome challenge delivery",
        phrase="captcha-delivery.com",
    ),
    Marker(
        kind="generic",
        description="page contains DataDome challenge copy",
        phrase="please enable js and disable any ad blocker",
    ),
    Marker(
        kind="generic",
        description="page contains a DataDome CAPTCHA iframe",
        phrase="datadome captcha",
    ),
)

_ALL_MARKERS: tuple[Marker, ...] = (
    (_CLOUDFLARE_TITLE_MARKER,) + _CLOUDFLARE_BODY_MARKERS + _GENERIC_MARKERS
)


def detect_antibot_html(html: str | None) -> AntibotDetection | None:
    """Return a normalized detection if HTML appears to be an anti-bot challenge."""
    if not html:
        return None

    lowered = html.lower()

    matches = [marker for marker in _ALL_MARKERS if marker.phrase in lowered]

    cloudflare_detection = _detect_cloudflare(matches)
    if cloudflare_detection:
        return cloudflare_detection

    for marker in matches:
        if marker.kind == "cloudflare":
            continue
        reason = f"{marker.description} (matched '{marker.phrase}')"
        return AntibotDetection(challenge_kind=marker.kind, reason=reason)

    return None


def is_antibot_html(html: str | None) -> bool:
    """Return True when the HTML matches one of the anti-bot markers."""
    return detect_antibot_html(html) is not None


def _detect_cloudflare(matches: Sequence[Marker]) -> AntibotDetection | None:
    """Return a detection only when both title and body markers are present."""
    cloudflare_matches = [marker for marker in matches if marker.kind == "cloudflare"]
    title_hit = next((marker for marker in cloudflare_matches if marker.is_title), None)
    body_hit = next(
        (marker for marker in cloudflare_matches if not marker.is_title),
        None,
    )
    if title_hit and body_hit:
        reason = (
            f"{title_hit.description}; {body_hit.description} "
            f"(matched '{body_hit.phrase}')"
        )
        return AntibotDetection(challenge_kind="cloudflare", reason=reason)
    return None
