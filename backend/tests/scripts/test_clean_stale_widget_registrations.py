import importlib.util
import subprocess
import sys
from pathlib import Path


def _load_helper_module():
    helper_path = Path(__file__).resolve().parents[3] / "scripts" / "clean_stale_widget_registrations.py"
    module_name = "scripts.clean_stale_widget_registrations"
    spec = importlib.util.spec_from_file_location(module_name, helper_path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader:
        sys.modules[module_name] = module
        spec.loader.exec_module(module)
    return module


def _load_fixture_text():
    fixture = (
        Path(__file__).resolve().parent
        / "fixtures"
        / "widget_registration_pluginkit_sample.txt"
    )
    return fixture.read_text()


def _stub_pluginkit_run(monkeypatch, helper, stdout, *, allow_removal=True):
    calls = []

    def fake_run(cmd, *args, **kwargs):
        calls.append(cmd)
        if cmd[:5] == ["pluginkit", "-m", "-A", "-D", "-v"]:
            return subprocess.CompletedProcess(cmd, 0, stdout=stdout)
        if cmd[:2] == ["pluginkit", "-r"]:
            if not allow_removal:
                raise AssertionError(f"Removal should not run during this test: {cmd}")
            return subprocess.CompletedProcess(cmd, 0, stdout="")
        raise AssertionError(f"Unexpected pluginkit invocation: {cmd}")

    monkeypatch.setattr(helper.subprocess, "run", fake_run)
    return calls


def test_widget_registration_parsing_and_classification():
    helper = _load_helper_module()
    fixture = (
        Path(__file__).resolve().parent
        / "fixtures"
        / "widget_registration_pluginkit_sample.txt"
    )
    lines = [line for line in fixture.read_text().splitlines()]

    block_sample = [
        "+    ai.sidebar.sidebar.sideBarWidgets(1.0)",
        "Path = /private/tmp/block/sideBarWidgetsExtension.appex",
        "Flags = worktree, debug",
        "",
    ]
    multiple_formats = helper.parse_pluginkit_output(block_sample)
    assert multiple_formats[0].raw_flags == ("worktree", "debug")

    records = helper.parse_pluginkit_output(lines)
    assert len(records) == 8

    assert records[0].raw_flags == ()
    assert records[0].uuid == "693D8320-0F9F-421A-A86B-FF4B669DAB69"
    assert records[0].timestamp == "2026-03-14 17:23:48 +0000"

    workspace_root = Path("/Users/sean/Coding/sideBar")
    classification = helper.classify_registrations(
        records, current_workspace=workspace_root
    )
    classification_repeat = helper.classify_registrations(
        records, current_workspace=workspace_root
    )
    assert classification_repeat == classification

    assert {record.path for record in classification.current_workspace} == {
        Path(
            "/Users/sean/Coding/sideBar/DerivedData/sideBar-gnsqvopaikzkhgcrhxxpjnkkoblk/Build/Products/Debug/sideBar.app/Contents/PlugIns/sideBarWidgetsExtension.appex"
        )
    }
    assert classification.current_workspace[0].raw_flags == ()
    assert {record.path for record in classification.installed_app} == {
        Path("/Applications/sideBar AI.app/Contents/PlugIns/sideBarWidgetsExtension.appex")
    }
    assert classification.installed_app[0].raw_flags == ()
    extra_private_tmp = Path("/private/tmp/sideBarWidgetStaging/sideBarWidgetsExtension.appex")
    assert {record.path for record in classification.unknown_non_debug} == {
        Path("/Users/sean/Downloads/sideBarWidgets/Release/sideBarWidgetsExtension.appex"),
        Path(
            "/Users/sean/Library/Application Support/sideBarWidgets/sideBarWidgetsExtension.appex"
        ),
        extra_private_tmp,
    }
    assert any(record.path == extra_private_tmp for record in classification.unknown_non_debug)
    stale_paths = {
        Path(
            "/Users/sean/.git/worktrees/widget/mac/DerivedData/sideBarWidgets/Build/Products/Debug/sideBarWidgetsExtension.appex"
        ),
        Path(
            "/private/tmp/sideBarWidgetStaging/Build/Products/Debug/sideBarWidgetsExtension.appex"
        ),
        Path(
            "/Users/sean/DerivedData/sideBarWidgets-Old/Build/Products/Debug/sideBarWidgetsExtension.appex"
        ),
    }
    assert {record.path for record in classification.stale_debug} == stale_paths
    assert not any(
        record.path == extra_private_tmp for record in classification.stale_debug
    )
    assert helper.should_keep_registration(classification.current_workspace[0], workspace_root)
    assert helper.should_keep_registration(classification.installed_app[0], workspace_root)
    for record in classification.unknown_non_debug:
        assert helper.should_keep_registration(record, workspace_root)
    for stale in classification.stale_debug:
        assert not helper.should_keep_registration(stale, workspace_root)

    kept_records = [record for record in records if record not in classification.stale_debug]
    classification_second = helper.classify_registrations(
        kept_records, current_workspace=workspace_root
    )
    assert not classification_second.stale_debug
    assert {record.path for record in classification_second.current_workspace} == {
        Path(
            "/Users/sean/Coding/sideBar/DerivedData/sideBar-gnsqvopaikzkhgcrhxxpjnkkoblk/Build/Products/Debug/sideBar.app/Contents/PlugIns/sideBarWidgetsExtension.appex"
        )
    }
    assert {record.path for record in classification_second.installed_app} == {
        Path("/Applications/sideBar AI.app/Contents/PlugIns/sideBarWidgetsExtension.appex")
    }
    assert {record.path for record in classification_second.unknown_non_debug} == {
        Path("/Users/sean/Downloads/sideBarWidgets/Release/sideBarWidgetsExtension.appex"),
        Path(
            "/Users/sean/Library/Application Support/sideBarWidgets/sideBarWidgetsExtension.appex"
        ),
        extra_private_tmp,
    }


def test_cli_dry_run_reports_summary_and_skips_removal(monkeypatch, capsys):
    helper = _load_helper_module()
    fixture_text = _load_fixture_text()
    calls = _stub_pluginkit_run(
        monkeypatch, helper, fixture_text, allow_removal=False
    )
    exit_code = helper.run_cleaner(
        [
            "--workspace-root",
            "/Users/sean/Coding/sideBar",
            "--bundle-id",
            "ai.sidebar.sidebar.sideBarWidgets",
            "--dry-run",
        ]
    )
    captured = capsys.readouterr()
    assert exit_code == 0
    assert "before cleanup" in captured.out.lower()
    assert "Dry run" in captured.out
    assert "Registration summary after cleanup" in captured.out
    assert not any(cmd[:2] == ["pluginkit", "-r"] for cmd in calls)


def test_cli_removes_stale_debug_registrations(monkeypatch):
    helper = _load_helper_module()
    fixture_text = _load_fixture_text()
    calls = _stub_pluginkit_run(monkeypatch, helper, fixture_text)
    exit_code = helper.run_cleaner(
        [
            "--workspace-root",
            "/Users/sean/Coding/sideBar",
            "--bundle-id",
            "ai.sidebar.sidebar.sideBarWidgets",
        ]
    )
    assert exit_code == 0
    removal_cmds = [cmd for cmd in calls if cmd[:2] == ["pluginkit", "-r"]]
    assert removal_cmds == [
        ["pluginkit", "-r", "F437C11D-2B23-4352-A1E9-583D840B315C"],
        ["pluginkit", "-r", "6AC0EA4E-7D4D-4D92-B68B-D96C36FA26D3"],
        ["pluginkit", "-r", "1B84CFE3-C17B-4EC5-9A72-8D1785B7E3C6"],
    ]


def test_cli_requires_current_workspace_registration(monkeypatch, capsys):
    helper = _load_helper_module()
    fixture_text = _load_fixture_text()
    calls = _stub_pluginkit_run(monkeypatch, helper, fixture_text)
    exit_code = helper.run_cleaner(
        [
            "--workspace-root",
            "/tmp/other-workspace",
            "--bundle-id",
            "ai.sidebar.sidebar.sideBarWidgets",
        ]
    )
    captured = capsys.readouterr()
    assert exit_code == 1
    assert "current workspace" in captured.out.lower()
    assert not any(cmd[:2] == ["pluginkit", "-r"] for cmd in calls)


def test_cli_fails_when_conflicting_stale_registrations_remain(monkeypatch, capsys):
    helper = _load_helper_module()
    workspace_line = _load_fixture_text().splitlines()[0]
    conflict_block = (
        "+    ai.sidebar.sidebar.sideBarWidgets(0.1)\n"
        "Path = /private/tmp/conflict/Build/Products/Debug/sideBarWidgetsExtension.appex\n"
        "Flags = debug\n"
        "\n"
    )
    listing = f"{workspace_line}\n{conflict_block}"
    calls = _stub_pluginkit_run(monkeypatch, helper, listing, allow_removal=False)
    exit_code = helper.run_cleaner(
        [
            "--workspace-root",
            "/Users/sean/Coding/sideBar",
            "--bundle-id",
            "ai.sidebar.sidebar.sideBarWidgets",
        ]
    )
    captured = capsys.readouterr()
    assert exit_code == 1
    assert "/private/tmp/conflict" in captured.out
    assert not any(cmd[:2] == ["pluginkit", "-r"] for cmd in calls)
