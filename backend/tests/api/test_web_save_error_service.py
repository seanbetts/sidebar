"""Tests for shared web-save error classification helpers."""

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
