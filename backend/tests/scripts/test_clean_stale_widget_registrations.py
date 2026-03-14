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
    listing_outputs = stdout if isinstance(stdout, list) else [stdout]
    listing_call_count = 0

    def fake_run(cmd, *args, **kwargs):
        nonlocal listing_call_count
        calls.append(cmd)
        if cmd[:5] == ["pluginkit", "-m", "-A", "-D", "-v"]:
            response_index = min(listing_call_count, len(listing_outputs) - 1)
            listing_call_count += 1
            return subprocess.CompletedProcess(
                cmd, 0, stdout=listing_outputs[response_index]
            )
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
    assert "Registration summary before cleanup" in captured.out
    assert "Dry run" in captured.out
    assert "Registration summary after cleanup" in captured.out
    assert "pluginkit -r" in captured.out
    assert not any(cmd[:2] == ["pluginkit", "-r"] for cmd in calls)


def test_cli_removes_stale_debug_registrations(monkeypatch):
    helper = _load_helper_module()
    fixture_text = _load_fixture_text()
    removed_uuids = {
        "F437C11D-2B23-4352-A1E9-583D840B315C",
        "6AC0EA4E-7D4D-4D92-B68B-D96C36FA26D3",
        "1B84CFE3-C17B-4EC5-9A72-8D1785B7E3C6",
    }
    post_cleanup_listing = "\n".join(
        line
        for line in fixture_text.splitlines()
        if not any(uuid in line for uuid in removed_uuids)
    )
    calls = _stub_pluginkit_run(
        monkeypatch,
        helper,
        [fixture_text, post_cleanup_listing],
    )
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


def test_cli_listing_failure_is_nonfatal(monkeypatch, capsys):
    helper = _load_helper_module()

    def _raise_listing_error():
        raise subprocess.CalledProcessError(
            2,
            ["pluginkit", "-m", "-A", "-D", "-v"],
            stderr="Connection invalid",
        )

    monkeypatch.setattr(helper, "_list_widget_registrations", _raise_listing_error)
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
    assert "pluginkit failed to list widget registrations" in captured.out
    assert "Connection invalid" in captured.out


def test_cli_fails_when_stale_debug_remains_after_attempted_cleanup(monkeypatch, capsys):
    helper = _load_helper_module()
    fixture_text = _load_fixture_text()
    post_cleanup_conflict = (
        "     ai.sidebar.sidebar.sideBarWidgets(0.1)\t693D8320-0F9F-421A-A86B-FF4B669DAB69\t2026-03-14 17:23:48 +0000\t"
        "/Users/sean/Coding/sideBar/DerivedData/sideBar-gnsqvopaikzkhgcrhxxpjnkkoblk/Build/Products/Debug/sideBar.app/Contents/PlugIns/sideBarWidgetsExtension.appex\n"
        "     ai.sidebar.sidebar.sideBarWidgets(0.1)\tBADBAD00-1111-2222-3333-444444444444\t2026-03-14 17:18:00 +0000\t"
        "/private/tmp/sideBarWidgetStaging/Build/Products/Debug/sideBarWidgetsExtension.appex\n"
    )
    calls = _stub_pluginkit_run(
        monkeypatch,
        helper,
        [fixture_text, post_cleanup_conflict],
    )
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
    assert "after attempted cleanup" in captured.out.lower()
    assert (
        "/private/tmp/sideBarWidgetStaging/Build/Products/Debug/sideBarWidgetsExtension.appex"
        in captured.out
    )
    removal_cmds = [cmd for cmd in calls if cmd[:2] == ["pluginkit", "-r"]]
    assert removal_cmds == [
        ["pluginkit", "-r", "F437C11D-2B23-4352-A1E9-583D840B315C"],
        ["pluginkit", "-r", "6AC0EA4E-7D4D-4D92-B68B-D96C36FA26D3"],
        ["pluginkit", "-r", "1B84CFE3-C17B-4EC5-9A72-8D1785B7E3C6"],
    ]


def test_cli_post_cleanup_verification_failure_is_nonfatal(monkeypatch, capsys):
    helper = _load_helper_module()
    before_cleanup = helper.ClassificationResult(
        current_workspace=[
            helper.WidgetRegistration(
                identifier="ai.sidebar.sidebar.sideBarWidgets",
                path=Path(
                    "/Users/sean/Coding/sideBar/DerivedData/sideBar/Build/Products/Debug/sideBar.app/Contents/PlugIns/sideBarWidgetsExtension.appex"
                ),
                uuid="WORKSPACE-UUID",
            )
        ],
        installed_app=[],
        stale_debug=[],
        unknown_non_debug=[],
    )
    load_calls = []

    def fake_load_bundle_classification(workspace_root, bundle_id):
        load_calls.append((workspace_root, bundle_id))
        if len(load_calls) == 1:
            return before_cleanup
        raise subprocess.CalledProcessError(
            2,
            ["pluginkit", "-m", "-A", "-D", "-v"],
            stderr="Connection invalid",
        )

    removal_calls = []

    def fake_remove_widget_registration(uuid):
        removal_calls.append(uuid)

    monkeypatch.setattr(
        helper, "_load_bundle_classification", fake_load_bundle_classification
    )
    monkeypatch.setattr(helper, "_remove_widget_registration", fake_remove_widget_registration)

    exit_code = helper.run_cleaner(
        [
            "--workspace-root",
            "/Users/sean/Coding/sideBar",
            "--bundle-id",
            "ai.sidebar.sidebar.sideBarWidgets",
        ]
    )
    captured = capsys.readouterr()

    assert exit_code == 0
    assert "Skipping post-cleanup verification." in captured.out
    assert removal_calls == []


def test_cli_post_cleanup_verification_failure_after_cleanup_is_fatal(
    monkeypatch, capsys
):
    helper = _load_helper_module()
    before_cleanup = helper.ClassificationResult(
        current_workspace=[
            helper.WidgetRegistration(
                identifier="ai.sidebar.sidebar.sideBarWidgets",
                path=Path(
                    "/Users/sean/Coding/sideBar/DerivedData/sideBar/Build/Products/Debug/sideBar.app/Contents/PlugIns/sideBarWidgetsExtension.appex"
                ),
                uuid="WORKSPACE-UUID",
            )
        ],
        installed_app=[],
        stale_debug=[
            helper.WidgetRegistration(
                identifier="ai.sidebar.sidebar.sideBarWidgets",
                path=Path(
                    "/private/tmp/sideBarWidgetStaging/Build/Products/Debug/sideBarWidgetsExtension.appex"
                ),
                uuid="STALE-UUID",
            )
        ],
        unknown_non_debug=[],
    )
    load_calls = []

    def fake_load_bundle_classification(workspace_root, bundle_id):
        load_calls.append((workspace_root, bundle_id))
        if len(load_calls) == 1:
            return before_cleanup
        raise subprocess.CalledProcessError(
            2,
            ["pluginkit", "-m", "-A", "-D", "-v"],
            stderr="Connection invalid",
        )

    removal_calls = []

    def fake_remove_widget_registration(uuid):
        removal_calls.append(uuid)

    monkeypatch.setattr(
        helper, "_load_bundle_classification", fake_load_bundle_classification
    )
    monkeypatch.setattr(helper, "_remove_widget_registration", fake_remove_widget_registration)

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
    assert "unresolved conflicting state" in captured.out
    assert removal_calls == ["STALE-UUID"]
