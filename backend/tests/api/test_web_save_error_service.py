"""Tests for shared web-save error classification helpers."""

from api.services.web_save_antibot import AntibotDetection
from api.services.web_save_error_service import (
    classify_web_save_failure,
    classify_web_save_result,
    decode_job_error,
    encode_job_error,
)


def test_classify_local_parse_and_jina_payment_required():
    payload = classify_web_save_failure(
        upstream_error_type="FetchError",
        upstream_message=(
            "Failed to fetch content from Jina.ai: "
            "402 Client Error: Payment Required"
        ),
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error="No readable content extracted",
    )

    assert payload["code"] == "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED"
    assert payload["details"]["http_status_code"] == 402
    assert payload["details"]["bug_report_context"]["error_code"] == payload["code"]


def test_classify_local_parse_and_jina_payment_required_includes_ssl_hint():
    payload = classify_web_save_failure(
        upstream_error_type="RequestException",
        upstream_message=(
            "Failed to fetch content from Jina.ai: "
            "402 Client Error: Payment Required"
        ),
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error=(
            "HTTPSConnectionPool(host='example.com', port=443): "
            "SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED]"
        ),
    )

    assert payload["code"] == "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED"
    assert any(
        "REQUESTS_CA_BUNDLE/SSL_CERT_FILE" in suggestion
        for suggestion in payload["suggestions"]
    )


def test_classify_wsj_preview_and_jina_payment_required_is_specific():
    payload = classify_web_save_failure(
        upstream_error_type="RequestException",
        upstream_message=(
            "Failed to fetch content from Jina.ai: "
            "402 Client Error: Payment Required"
        ),
        url="https://www.wsj.com/tech/ai/story-id",
        target_url="https://www.wsj.com/tech/ai/story-id",
        mode="local",
        local_parse_error=(
            "WSJ preview detected but Jina fallback failed: "
            "authenticated request returned 402 and anonymous fallback failed: "
            "Client error '451 Unavailable For Legal Reasons'"
        ),
    )

    assert payload["code"] == "WEB_SAVE_LOCAL_PARSE_AND_JINA_PAYMENT_REQUIRED"
    assert "WSJ preview content was detected" in payload["message"]
    assert any("HTTP 451" in suggestion for suggestion in payload["suggestions"])


def test_classify_web_save_result_preserves_structured_payload():
    result = {
        "success": False,
        "error": {
            "type": "FetchError",
            "code": "WEB_SAVE_JINA_PAYMENT_REQUIRED",
            "message": (
                "Unable to save website: Jina fallback returned 402 Payment Required."
            ),
            "details": {"http_status_code": 402},
            "suggestions": ["Check JINA_API_KEY billing/quota status."],
        },
    }

    payload = classify_web_save_result(
        result,
        url="https://example.com",
        target_url="https://example.com",
        mode="jina",
    )

    assert payload["code"] == "WEB_SAVE_JINA_PAYMENT_REQUIRED"
    assert payload["details"]["url"] == "https://example.com"
    assert payload["details"]["mode"] == "jina"


def test_decode_job_error_round_trip():
    payload = classify_web_save_failure(
        upstream_error_type="FetchError",
        upstream_message="Failed to fetch content from Jina.ai: 402 Client Error",
    )
    encoded = encode_job_error(payload)
    message, decoded = decode_job_error(encoded)

    assert message == payload["message"]
    assert decoded is not None
    assert decoded["code"] == payload["code"]


def test_decode_job_error_handles_plain_text():
    message, decoded = decode_job_error("plain failure message")
    assert message == "plain failure message"
    assert decoded is None


def test_classify_antibot_blocked_site_code_for_blocked_content():
    detection = AntibotDetection("cloudflare", "Just a moment challenge")
    payload = classify_web_save_failure(
        upstream_error_type="FetchError",
        upstream_message="Jina returned anti-bot challenge HTML",
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error=(
            "Local parser requested fallback='jina' via rule 'antibot-fetch-challenge' "
            "antibot=cloudflare:Just a moment challenge stage=fetch"
        ),
        local_antibot_detection=detection,
        local_antibot_stage="fetch",
        local_antibot_rule_id="antibot-fetch-challenge",
        upstream_antibot_detection=detection,
        fallback_outcome="blocked_content",
    )

    assert payload["code"] == "WEB_SAVE_BLOCKED_SITE"
    assert payload["details"]["antibot_challenge_kind"] == "cloudflare"
    assert payload["details"]["antibot_stage"] == "fetch"
    assert "blocked" in payload["message"].lower()
    assert payload["details"]["bug_report_context"]["error_code"] == payload["code"]


def test_classify_antibot_blocked_site_code_for_timeout():
    detection = AntibotDetection("generic", "challenge-form detected")
    payload = classify_web_save_failure(
        upstream_error_type="FetchError",
        upstream_message="Failed to fetch content from Jina.ai: request timed out",
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error=(
            "Local parser requested fallback='jina' via rule 'antibot-fetch-challenge' "
            "antibot=generic:challenge-form detected stage=fetch"
        ),
        local_antibot_detection=detection,
        local_antibot_stage="fetch",
        local_antibot_rule_id="antibot-fetch-challenge",
        fallback_outcome="timeout",
    )

    assert payload["code"] == "WEB_SAVE_BLOCKED_SITE"
    assert payload["details"]["fallback_outcome"] == "timeout"
    assert any("anti-bot" in suggestion.lower() for suggestion in payload["suggestions"])


def test_classify_antibot_context_with_non_blocked_outcome_is_not_blocked():
    detection = AntibotDetection("generic", "challenge-form detected")
    payload = classify_web_save_failure(
        upstream_error_type="FetchError",
        upstream_message="Jina returned anti-bot challenge HTML",
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error="Local parser fallback triggered but handled gracefully.",
        local_antibot_detection=detection,
        local_antibot_stage="fetch",
        local_antibot_rule_id="antibot-fetch-challenge",
        fallback_outcome="other",
    )

    assert payload["code"] != "WEB_SAVE_BLOCKED_SITE"
    assert payload["details"]["fallback_outcome"] == "other"


def test_classify_antibot_context_without_outcome_is_not_blocked():
    detection = AntibotDetection("generic", "challenge-form detected")
    payload = classify_web_save_failure(
        upstream_error_type="FetchError",
        upstream_message="Jina returned anti-bot challenge HTML",
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error="Local parser fallback triggered but no fallback outcome yet.",
        local_antibot_detection=detection,
        local_antibot_stage="fetch",
        local_antibot_rule_id="antibot-fetch-challenge",
    )

    assert payload["code"] != "WEB_SAVE_BLOCKED_SITE"
    assert payload["details"].get("fallback_outcome") is None


def test_plain_local_parse_failure_with_jina_timeout_stays_generic():
    payload = classify_web_save_failure(
        upstream_error_type="Timeout",
        upstream_message="Failed to fetch content from Jina.ai: request timed out",
        url="https://example.com",
        target_url="https://example.com",
        mode="local",
        local_parse_error="Local parser failed without antibot detection.",
        fallback_outcome="timeout",
    )

    assert payload["code"] == "WEB_SAVE_LOCAL_PARSE_AND_JINA_FETCH_FAILED"
    assert payload["details"].get("fallback_outcome") == "timeout"
    assert payload["code"] != "WEB_SAVE_BLOCKED_SITE"
