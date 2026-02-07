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


def test_resolve_player_clients_defaults_for_audio(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_PLAYER_CLIENTS", raising=False)
    assert module._resolve_player_clients(audio_only=True) == ["tv", "ios"]


def test_resolve_player_clients_defaults_for_video(monkeypatch):
    module = _load_download_module()
    monkeypatch.delenv("YT_DLP_PLAYER_CLIENTS", raising=False)
    assert module._resolve_player_clients(audio_only=False) == ["tv", "ios", "web"]


def test_resolve_player_clients_from_env(monkeypatch):
    module = _load_download_module()
    monkeypatch.setenv("YT_DLP_PLAYER_CLIENTS", "ios, web, tv")
    assert module._resolve_player_clients(audio_only=True) == ["ios", "web", "tv"]
