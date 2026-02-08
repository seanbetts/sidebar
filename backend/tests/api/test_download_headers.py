from api.routers.download_headers import markdown_download_headers


def test_markdown_download_headers_supports_unicode_filenames():
    headers = markdown_download_headers("OpenClaw🦞.md")
    disposition = headers["Content-Disposition"]

    assert 'filename="OpenClaw.md"' in disposition
    assert "filename*=UTF-8''OpenClaw%F0%9F%A6%9E.md" in disposition
    assert "🦞" not in disposition


def test_markdown_download_headers_rejects_header_breaking_characters():
    headers = markdown_download_headers("line1\r\nline2.md")
    disposition = headers["Content-Disposition"]

    assert "\r" not in disposition
    assert "\n" not in disposition
    assert "line1 line2.md" in disposition
