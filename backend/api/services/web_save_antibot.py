"""Simple heuristics to detect Cloudflare or generic anti-bot HTML before rendering."""

from dataclasses import dataclass


@dataclass(frozen=True)
class AntibotDetection:
    """Represents a normalized anti-bot detection result."""

    challenge_kind: str
    reason: str


Marker = tuple[str, str, str]

_CLOUDFLARE_MARKERS: tuple[Marker, ...] = (
    ("cloudflare", "title contains 'Just a moment...'", "just a moment"),
    (
        "cloudflare",
        "body mentions 'Checking your browser before accessing'",
        "checking your browser before accessing",
    ),
    (
        "cloudflare",
        "page contains cf-browser-verification marker",
        "cf-browser-verification",
    ),
    ("cloudflare", "page contains cf-error-code marker", "cf-error-code"),
)

_GENERIC_MARKERS: tuple[Marker, ...] = (
    ("generic", "page includes a 'challenge-form' element", "challenge-form"),
    ("generic", "page tells the user to enable cookies", "enable cookies"),
    ("generic", "page warns to wait while verifying", "please wait while we verify"),
)

_ALL_MARKERS: tuple[Marker, ...] = _CLOUDFLARE_MARKERS + _GENERIC_MARKERS


def detect_antibot_html(html: str | None) -> AntibotDetection | None:
    """Return a normalized detection if HTML appears to be an anti-bot challenge."""
    if not html:
        return None

    lowered = html.lower()

    for kind, description, phrase in _ALL_MARKERS:
        if phrase in lowered:
            reason = f"{description} (matched '{phrase}')"
            return AntibotDetection(challenge_kind=kind, reason=reason)

    return None


def is_antibot_html(html: str | None) -> bool:
    """Return True when the HTML matches one of the anti-bot markers."""
    return detect_antibot_html(html) is not None
