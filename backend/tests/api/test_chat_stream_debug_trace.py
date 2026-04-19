from api.services.ai.chat_stream_debug_trace import (
    CHAT_STREAM_DEBUG_ENVIRONMENT_VARIABLE,
    is_chat_stream_debug_enabled,
    visible_whitespace_preview,
)


def test_is_chat_stream_debug_enabled_requires_explicit_one() -> None:
    assert is_chat_stream_debug_enabled(
        {CHAT_STREAM_DEBUG_ENVIRONMENT_VARIABLE: "1"}
    )
    assert not is_chat_stream_debug_enabled(
        {CHAT_STREAM_DEBUG_ENVIRONMENT_VARIABLE: "0"}
    )
    assert not is_chat_stream_debug_enabled({})


def test_visible_whitespace_preview_escapes_control_characters() -> None:
    assert (
        visible_whitespace_preview("Line 1\n\tLine 2\r\nLine 3")
        == r"Line 1\n\tLine 2\r\nLine 3"
    )


def test_visible_whitespace_preview_truncates_long_content() -> None:
    assert visible_whitespace_preview("abcdef", limit=4) == "abcd..."
