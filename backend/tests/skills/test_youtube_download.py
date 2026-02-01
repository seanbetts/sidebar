import importlib.util
from pathlib import Path


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


def test_resolve_js_runtimes_from_path(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_JS_RUNTIMES", raising=False)
    monkeypatch.delenv("YT_DLP_JS_RUNTIME", raising=False)
    monkeypatch.setattr(module.shutil, "which", lambda value: "/usr/bin/node" if value == "node" else None)
    assert module._resolve_js_runtimes() == {"node": {}}


def test_resolve_cookiefile_from_env(tmp_path, monkeypatch):
    module = _load_download_module()
    cookiefile = tmp_path / "cookies.txt"
    cookiefile.write_text("# Netscape HTTP Cookie File\n")
    monkeypatch.setenv("YT_DLP_COOKIES", str(cookiefile))
    monkeypatch.delenv("YT_DLP_COOKIES_PATH", raising=False)
    assert module._resolve_cookiefile() == str(cookiefile)


def test_resolve_cookiefile_missing(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_COOKIES", "/tmp/does-not-exist.txt")
    monkeypatch.delenv("YT_DLP_COOKIES_PATH", raising=False)
    try:
        module._resolve_cookiefile()
    except ValueError as exc:
        assert "cookies file" in str(exc).lower()
    else:
        raise AssertionError("Expected ValueError for missing cookie file")
