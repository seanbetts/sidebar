import importlib.util
from pathlib import Path
from types import SimpleNamespace
from typing import Any


def _load_download_module():
    script_path = (
        Path(__file__).resolve().parents[3]
        / "backend"
        / "skills"
        / "youtube-download"
        / "scripts"
        / "download_video.py"
    )
    spec = importlib.util.spec_from_file_location("youtube_download", script_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_resolve_js_runtimes_from_env(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_JS_RUNTIMES", "node")
    monkeypatch.delenv("YT_DLP_JS_RUNTIME", raising=False)
    assert module._resolve_js_runtimes() == {"node": {}}


def test_resolve_js_runtimes_from_env_with_path(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_JS_RUNTIMES", "node:/opt/node")
    monkeypatch.delenv("YT_DLP_JS_RUNTIME", raising=False)
    assert module._resolve_js_runtimes() == {"node": {"path": "/opt/node"}}


def test_resolve_js_runtimes_preserves_env_order(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_JS_RUNTIMES", "deno,node")
    monkeypatch.delenv("YT_DLP_JS_RUNTIME", raising=False)
    assert module._resolve_js_runtimes() == {"deno": {}, "node": {}}


def test_resolve_js_runtimes_from_path(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_JS_RUNTIMES", raising=False)
    monkeypatch.delenv("YT_DLP_JS_RUNTIME", raising=False)
    monkeypatch.setattr(module.shutil, "which", lambda value: "/usr/bin/node" if value == "node" else None)
    assert module._resolve_js_runtimes() == {"node": {}}


def test_resolve_js_runtimes_missing(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_JS_RUNTIMES", raising=False)
    monkeypatch.delenv("YT_DLP_JS_RUNTIME", raising=False)
    monkeypatch.setattr(module.shutil, "which", lambda _value: None)
    assert module._resolve_js_runtimes() is None


def test_detect_impersonation_support_when_curl_cffi_available(monkeypatch):
    module = _load_download_module()

    class FakeSpec:
        pass

    monkeypatch.setattr(
        module.importlib.util,
        "find_spec",
        lambda name: FakeSpec() if name == "curl_cffi" else None,
    )

    assert module._detect_impersonation_support() == "curl_cffi"


def test_detect_impersonation_support_when_unavailable(monkeypatch):
    module = _load_download_module()
    monkeypatch.setattr(module.importlib.util, "find_spec", lambda _name: None)

    assert module._detect_impersonation_support() == "none"


def test_resolve_youtube_webpage_client_from_env(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_YOUTUBE_WEBPAGE_CLIENT", "web")

    assert module._resolve_youtube_webpage_client() == "web"


def test_resolve_youtube_webpage_client_rejects_unknown_value(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_YOUTUBE_WEBPAGE_CLIENT", "desktop")

    assert module._resolve_youtube_webpage_client() is None


def test_resolve_player_clients_defaults_for_audio(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_PLAYER_CLIENTS", raising=False)
    assert module._resolve_player_clients(audio_only=True) == ["default"]


def test_resolve_player_clients_defaults_for_video(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_PLAYER_CLIENTS", raising=False)
    assert module._resolve_player_clients(audio_only=False) is None


def test_resolve_player_clients_from_env(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_PLAYER_CLIENTS", "ios, web, tv")
    assert module._resolve_player_clients(audio_only=True) == ["ios", "web", "tv"]


def test_default_remote_components_stays_enabled():
    module = _load_download_module()
    assert module._default_remote_components() == ["ejs:github"]


def test_download_youtube_enables_remote_components(monkeypatch, tmp_path):
    module = _load_download_module()
    captured: dict[str, Any] = {}
    log_messages: list[str] = []

    class FakeYoutubeDL:
        def __init__(self, opts):
            captured["opts"] = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, _url, download=False):
            assert download is False
            return {"title": "Video", "duration": 42}

        def prepare_filename(self, _info):
            return str(tmp_path / "Video.webm")

        def download(self, _urls):
            (tmp_path / "Video.mp3").write_bytes(b"audio")

    monkeypatch.setattr(module, "check_ffmpeg", lambda: True)
    monkeypatch.setattr(module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(module, "_resolve_js_runtimes", lambda: {"node": {}})
    monkeypatch.setattr(module, "_detect_impersonation_support", lambda: "curl_cffi")
    monkeypatch.setattr(
        module.logger,
        "info",
        lambda message, *args: log_messages.append(message % args if args else message),
    )

    result = module.download_youtube(
        url="https://www.youtube.com/watch?v=abc123xyzAA",
        audio_only=True,
        quiet=True,
        upload=False,
        temp_dir=str(tmp_path),
    )

    assert result["success"] is True
    assert captured["opts"]["remote_components"] == ["ejs:github"]
    assert captured["opts"]["extractor_args"] == {
        "youtube": {"player_client": ["default"]}
    }
    assert (
        'yt-dlp extractor args: {"youtube": {"player_client": ["default"]}}'
        in log_messages
    )
    assert "yt-dlp impersonation support: curl_cffi" in log_messages


def test_download_youtube_leaves_video_player_clients_on_default(monkeypatch, tmp_path):
    module = _load_download_module()
    captured: dict[str, Any] = {}

    class FakeYoutubeDL:
        def __init__(self, opts):
            captured["opts"] = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, _url, download=False):
            assert download is False
            return {"title": "Video", "duration": 42}

        def prepare_filename(self, _info):
            return str(tmp_path / "Video.webm")

        def download(self, _urls):
            (tmp_path / "Video.webm").write_bytes(b"video")

    monkeypatch.setattr(module, "check_ffmpeg", lambda: True)
    monkeypatch.setattr(module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(module, "_resolve_js_runtimes", lambda: {"node": {}})

    result = module.download_youtube(
        url="https://www.youtube.com/watch?v=abc123xyzAA",
        audio_only=False,
        quiet=True,
        upload=False,
        temp_dir=str(tmp_path),
    )

    assert result["success"] is True
    assert "extractor_args" not in captured["opts"]


def test_backend_lockfile_resolves_yt_dlp_nightly_build():
    lock_path = Path(__file__).resolve().parents[2] / "uv.lock"
    lock_content = lock_path.read_text()

    assert 'name = "yt-dlp"' in lock_content
    assert 'version = "2026.3.13.83652.dev0"' in lock_content
    assert 'name = "curl-cffi"' in lock_content


def test_download_youtube_adds_webpage_client_to_extractor_args(monkeypatch, tmp_path):
    module = _load_download_module()
    captured: dict[str, Any] = {}

    class FakeYoutubeDL:
        def __init__(self, opts):
            captured["opts"] = opts

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def extract_info(self, _url, download=False):
            assert download is False
            return {"title": "Video", "duration": 42}

        def prepare_filename(self, _info):
            return str(tmp_path / "Video.webm")

        def download(self, _urls):
            (tmp_path / "Video.mp3").write_bytes(b"audio")

    monkeypatch.setenv("YT_DLP_YOUTUBE_WEBPAGE_CLIENT", "web")
    monkeypatch.setattr(module, "check_ffmpeg", lambda: True)
    monkeypatch.setattr(module.yt_dlp, "YoutubeDL", FakeYoutubeDL)
    monkeypatch.setattr(module, "_resolve_js_runtimes", lambda: {"deno": {}})

    result = module.download_youtube(
        url="https://www.youtube.com/watch?v=abc123xyzAA",
        audio_only=True,
        quiet=True,
        upload=False,
        temp_dir=str(tmp_path),
    )

    assert result["success"] is True
    assert captured["opts"]["extractor_args"] == {
        "youtube": {"player_client": ["default"], "webpage_client": ["web"]}
    }


def test_store_downloaded_output_uses_ingestion_helpers(monkeypatch, tmp_path):
    module = _load_download_module()
    record = SimpleNamespace(id="abc123", path="files/videos/download.mp4")
    local_file = tmp_path / "download.mp4"
    local_file.write_bytes(b"abc")

    create_calls: dict[str, Any] = {}
    derivative_calls: dict[str, Any] = {}
    ai_calls: dict[str, Any] = {}
    transcribe_calls: dict[str, Any] = {}

    def fake_create_ingested_file(
        user_id,
        filename,
        mime,
        size,
        *,
        source_url=None,
        source_metadata=None,
        path=None,
        sha256=None,
    ):
        create_calls["user_id"] = user_id
        create_calls["filename"] = filename
        create_calls["mime"] = mime
        create_calls["size"] = size
        create_calls["source_url"] = source_url
        create_calls["source_metadata"] = source_metadata
        create_calls["path"] = path
        create_calls["sha256"] = sha256
        return record

    def fake_write_derivative(user_id, rec, path, *, kind, content_type=None):
        derivative_calls["user_id"] = user_id
        derivative_calls["record_id"] = rec.id
        derivative_calls["path"] = Path(path)
        derivative_calls["kind"] = kind
        derivative_calls["content_type"] = content_type
        return {
            "kind": kind,
            "storage_key": f"{user_id}/files/{rec.id}/derivatives/download.mp4",
            "mime": content_type or "video/mp4",
            "size_bytes": len(b"abc"),
            "sha256": "sha",
            "content_type": content_type or "video/mp4",
        }

    def fake_write_ai_markdown(user_id, rec, content, *, frontmatter, derivative_items):
        ai_calls["user_id"] = user_id
        ai_calls["record_id"] = rec.id
        ai_calls["content"] = content
        ai_calls["frontmatter"] = frontmatter
        ai_calls["derivative_items"] = derivative_items
        return {
            "kind": "ai_md",
            "storage_key": f"{user_id}/files/{rec.id}/ai/ai.md",
            "mime": "text/markdown",
            "size_bytes": 16,
            "sha256": "md",
            "content_type": "text/markdown",
        }

    def fake_transcribe_downloaded_media(*, local_output, user_id):
        transcribe_calls["local_output"] = Path(local_output)
        transcribe_calls["user_id"] = user_id
        return (
            "First transcript line.\nSecond transcript line.",
            {"model": "gpt-4o-transcribe"},
        )

    expected_payload = {"file_id": "abc123", "ai_path": "ai", "derivatives": []}

    def fake_finalize(user_id, rec, derivatives):
        assert derivatives[0]["kind"] == derivative_calls["kind"]
        assert derivatives[1]["kind"] == "ai_md"
        assert user_id == "user-1"
        assert rec.id == "abc123"
        return expected_payload

    monkeypatch.setattr(module, "upload_file", None)
    monkeypatch.setattr(module, "create_ingested_file", fake_create_ingested_file)
    monkeypatch.setattr(module, "write_derivative", fake_write_derivative)
    monkeypatch.setattr(module, "write_ai_markdown", fake_write_ai_markdown)
    monkeypatch.setattr(module, "finalize_ingested_file", fake_finalize)
    monkeypatch.setattr(
        module, "_transcribe_downloaded_media", fake_transcribe_downloaded_media
    )

    returned_record, payload = module._store_downloaded_output(
        user_id="user-1",
        local_output=local_file,
        r2_path="files/videos/download.mp4",
        processed_url="https://www.youtube.com/watch?v=abc123",
        title="Video Title",
        filename="download.mp4",
        audio_only=False,
        duration_seconds=135,
        download_duration_seconds=5,
    )

    assert returned_record is record
    assert payload is expected_payload
    assert create_calls["filename"] == "download.mp4"
    assert create_calls["mime"] == "video/mp4"
    assert create_calls["path"] == "files/videos/download.mp4"
    assert create_calls["source_url"] == "https://www.youtube.com/watch?v=abc123"
    assert create_calls["source_metadata"]["provider"] == "youtube-download"
    assert create_calls["source_metadata"]["duration_seconds"] == 135
    assert create_calls["source_metadata"]["download_duration_seconds"] == 5
    assert create_calls["source_metadata"]["transcript_status"] == "ready"
    assert create_calls["source_metadata"]["transcription_model"] == "gpt-4o-transcribe"
    assert derivative_calls["kind"] == "video_original"
    assert ai_calls["frontmatter"]["ingestion"]["skill"] == "youtube-download"
    assert ai_calls["frontmatter"]["ingestion"]["model"] == "gpt-4o-transcribe"
    assert ai_calls["frontmatter"]["ingestion"]["duration_seconds"] == 135
    assert ai_calls["frontmatter"]["ingestion"]["download_duration_seconds"] == 5
    assert ai_calls["content"].startswith("## Video Title\n\n")
    assert "First transcript line." in ai_calls["content"]
    assert "Download completed successfully." not in ai_calls["content"]
    assert ai_calls["derivative_items"][0]["kind"] == "video_original"
    assert ai_calls["derivative_items"][0]["path"].endswith("download.mp4")
    assert transcribe_calls["user_id"] == "user-1"
    assert transcribe_calls["local_output"] == local_file


def test_store_downloaded_output_falls_back_to_upload_file(monkeypatch, tmp_path):
    module = _load_download_module()
    record = SimpleNamespace(id="upload-id", path="files/videos/download.mp4")
    local_file = tmp_path / "download.mp4"
    local_file.write_bytes(b"abc")

    upload_calls: dict[str, Any] = {}

    def fake_upload_file(user_id, r2_path, path, content_type=None):
        upload_calls["user_id"] = user_id
        upload_calls["r2_path"] = r2_path
        upload_calls["path"] = Path(path)
        upload_calls["content_type"] = content_type
        return record

    monkeypatch.setattr(module, "create_ingested_file", None)
    monkeypatch.setattr(module, "write_derivative", None)
    monkeypatch.setattr(module, "write_ai_markdown", None)
    monkeypatch.setattr(module, "finalize_ingested_file", None)
    monkeypatch.setattr(module, "upload_file", fake_upload_file)
    monkeypatch.setattr(
        module,
        "_transcribe_downloaded_media",
        lambda *, local_output, user_id: ("", {"model": "gpt-4o-transcribe"}),
    )

    returned_record, payload = module._store_downloaded_output(
        user_id="user-1",
        local_output=local_file,
        r2_path="files/videos/download.mp4",
        processed_url="https://www.youtube.com/watch?v=abc123",
        title="Video Title",
        filename="download.mp4",
        audio_only=False,
        duration_seconds=42,
        download_duration_seconds=2,
    )

    assert returned_record is record
    assert upload_calls["user_id"] == "user-1"
    assert upload_calls["r2_path"] == "files/videos/download.mp4"
    assert upload_calls["path"] == local_file
    assert upload_calls["content_type"] == "video/mp4"
    assert payload["file_id"] == "upload-id"
    assert payload["derivatives"][0]["kind"] == "video_original"


def test_store_downloaded_output_marks_transcript_failure(monkeypatch, tmp_path):
    module = _load_download_module()
    record = SimpleNamespace(id="abc123", path="files/videos/download.mp4")
    local_file = tmp_path / "download.mp4"
    local_file.write_bytes(b"abc")

    create_calls: dict[str, Any] = {}
    ai_calls: dict[str, Any] = {}

    def fake_create_ingested_file(
        user_id,
        filename,
        mime,
        size,
        *,
        source_url=None,
        source_metadata=None,
        path=None,
        sha256=None,
    ):
        create_calls["source_metadata"] = source_metadata
        return record

    def fake_write_derivative(user_id, rec, path, *, kind, content_type=None):
        return {
            "kind": kind,
            "storage_key": f"{user_id}/files/{rec.id}/derivatives/download.mp4",
            "mime": content_type or "video/mp4",
            "size_bytes": len(b"abc"),
            "sha256": "sha",
            "content_type": content_type or "video/mp4",
        }

    def fake_write_ai_markdown(user_id, rec, content, *, frontmatter, derivative_items):
        ai_calls["content"] = content
        ai_calls["frontmatter"] = frontmatter
        return {
            "kind": "ai_md",
            "storage_key": f"{user_id}/files/{rec.id}/ai/ai.md",
            "mime": "text/markdown",
            "size_bytes": 16,
            "sha256": "md",
            "content_type": "text/markdown",
        }

    monkeypatch.setattr(module, "upload_file", None)
    monkeypatch.setattr(module, "create_ingested_file", fake_create_ingested_file)
    monkeypatch.setattr(module, "write_derivative", fake_write_derivative)
    monkeypatch.setattr(module, "write_ai_markdown", fake_write_ai_markdown)
    monkeypatch.setattr(module, "finalize_ingested_file", lambda user_id, rec, derivatives: {})

    def fail_transcribe(*, local_output, user_id):
        raise RuntimeError("OPENAI_API_KEY environment variable is not set")

    monkeypatch.setattr(module, "_transcribe_downloaded_media", fail_transcribe)

    module._store_downloaded_output(
        user_id="user-1",
        local_output=local_file,
        r2_path="files/videos/download.mp4",
        processed_url="https://www.youtube.com/watch?v=abc123",
        title="Video Title",
        filename="download.mp4",
        audio_only=False,
        duration_seconds=135,
        download_duration_seconds=5,
    )

    assert create_calls["source_metadata"]["transcript_status"] == "failed"
    assert "OPENAI_API_KEY" in create_calls["source_metadata"]["transcript_error"]
    assert ai_calls["content"].startswith("## Video Title")
    assert "Transcript unavailable for this video." in ai_calls["content"]
    assert ai_calls["frontmatter"]["ingestion"]["skill"] == "youtube-download"


def test_format_human_readable_prefers_media_duration():
    module = _load_download_module()
    rendered = module.format_human_readable(
        {
            "title": "Video Title",
            "url": "https://www.youtube.com/watch?v=abc123",
            "audio_only": False,
            "is_playlist": False,
            "output_dir": "files/videos",
            "filename": "video.mp4",
            "duration_seconds": 135,
            "download_duration_seconds": 7,
        }
    )

    assert "Media duration: 2m 15s" in rendered
    assert "Download time: 0m 7s" in rendered


def test_parse_ffprobe_json_tolerates_prefixed_noise():
    module = _load_download_module()
    payload = module._parse_ffprobe_json("ffprobe warning\n{\n  \"streams\": []\n}")
    assert payload == {"streams": []}


def test_verify_output_quiet_suppresses_stdout_on_parse_error(monkeypatch, capsys):
    module = _load_download_module()

    class _Result:
        def __init__(self, stdout: str):
            self.stdout = stdout

    results = iter([_Result("  not-json"), _Result("  not-json")])

    def fake_run(*_args, **_kwargs):
        return next(results)

    monkeypatch.setattr(module.subprocess, "run", fake_run)

    assert module.verify_output("/tmp/out.mp4", quiet=True) is False
    captured = capsys.readouterr()
    assert captured.out == ""
