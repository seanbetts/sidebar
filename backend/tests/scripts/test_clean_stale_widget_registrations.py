import importlib.util
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
    assert len(records) == 7

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
    assert {record.path for record in classification.unknown_non_debug} == {
        Path("/Users/sean/Downloads/sideBarWidgets/Release/sideBarWidgetsExtension.appex"),
        Path(
            "/Users/sean/Library/Application Support/sideBarWidgets/sideBarWidgetsExtension.appex"
        ),
    }
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
    }
