"""Tests for SkillExecutor security and functionality."""

from __future__ import annotations

import asyncio
import json
import subprocess
import threading
from pathlib import Path
from types import SimpleNamespace

import pytest
from api.config import settings
from api.services.agent.skills.executor import SkillExecutor


@pytest.fixture
def temp_skills_dir(tmp_path):
    """Create a temporary skills directory for testing."""
    skills_dir = tmp_path / "skills"
    skills_dir.mkdir()

    # Create a test skill with a simple script
    test_skill = skills_dir / "test-skill"
    test_skill.mkdir()
    scripts_dir = test_skill / "scripts"
    scripts_dir.mkdir()

    # Create a simple test script that echoes JSON
    test_script = scripts_dir / "echo.py"
    test_script.write_text("""#!/usr/bin/env python3
import sys
import json
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("message")
parser.add_argument("--json", action="store_true")
args = parser.parse_args()

result = {
    "success": True,
    "data": {"message": args.message}
}

if args.json:
    print(json.dumps(result))
else:
    print(result["data"]["message"])
""")

    return skills_dir


@pytest.fixture
def temp_workspace(tmp_path):
    """Create a temporary workspace for testing."""
    workspace = tmp_path / "workspace"
    workspace.mkdir()
    (workspace / "test.txt").write_text("test content")
    return workspace


@pytest.fixture
def executor(temp_skills_dir, temp_workspace):
    """Create a SkillExecutor for testing."""
    executor = SkillExecutor(temp_skills_dir, temp_workspace)
    # Add test-skill to allowed list
    executor.allowed_skills.add("test-skill")
    return executor


class TestSkillExecutorValidation:
    """Test script path validation."""

    @pytest.mark.asyncio
    async def test_execute_valid_skill(self, executor):
        """Should execute whitelisted skills."""
        result = await executor.execute("test-skill", "echo.py", ["hello"])
        assert result["success"] is True
        assert result["data"]["message"] == "hello"

    @pytest.mark.asyncio
    async def test_rejects_non_whitelisted_skill(self, executor):
        """Should reject skills not in allowlist."""
        result = await executor.execute("malicious-skill", "evil.py", [])
        assert result["success"] is False
        assert "not allowed" in result["error"]

    @pytest.mark.asyncio
    async def test_rejects_non_python_scripts(self, executor, temp_skills_dir):
        """Should reject non-Python scripts."""
        # Create a shell script
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        shell_script = test_skill / "malicious.sh"
        shell_script.write_text("#!/bin/bash\nrm -rf /")

        result = await executor.execute("test-skill", "malicious.sh", [])
        assert result["success"] is False
        assert "Only Python scripts allowed" in result["error"]

    @pytest.mark.asyncio
    async def test_rejects_path_traversal_in_script(self, executor):
        """Should reject path traversal attempts in script name."""
        result = await executor.execute("test-skill", "../../etc/passwd", [])
        assert result["success"] is False
        assert "outside skills directory" in result["error"]

    @pytest.mark.asyncio
    async def test_rejects_missing_script(self, executor):
        """Should handle missing scripts gracefully."""
        result = await executor.execute("test-skill", "nonexistent.py", [])
        assert result["success"] is False
        assert "not found" in result["error"]


class TestSkillExecutorSecurity:
    """Test security measures."""

    @pytest.mark.asyncio
    async def test_validates_workspace_paths_in_args(self, executor):
        """Should reject path traversal in arguments."""
        result = await executor.execute("test-skill", "echo.py", ["../../etc/passwd"])
        assert result["success"] is False
        assert "Path traversal not allowed" in result["error"]

    @pytest.mark.asyncio
    async def test_timeout_enforcement(self, executor, temp_skills_dir):
        """Should enforce execution timeout."""
        # Create a script that sleeps
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        slow_script = test_skill / "slow.py"
        slow_script.write_text("""#!/usr/bin/env python3
import time
import json
time.sleep(60)  # Sleep longer than timeout
print(json.dumps({"success": True}))
""")

        # Set a short timeout
        original_timeout = settings.skill_timeout_seconds
        settings.skill_timeout_seconds = 1

        try:
            result = await executor.execute("test-skill", "slow.py", [])
            assert result["success"] is False
            assert "timeout" in result["error"].lower()
        finally:
            settings.skill_timeout_seconds = original_timeout

    @pytest.mark.asyncio
    async def test_timeout_logs_partial_subprocess_output(
        self, executor, monkeypatch, caplog
    ):
        """Timeouts should log any partial stdout/stderr emitted before the kill."""

        def fake_run(*args, **kwargs):
            raise subprocess.TimeoutExpired(
                cmd=kwargs.get("args", args[0] if args else ["python", "slow.py"]),
                timeout=kwargs["timeout"],
                output="partial stdout before timeout",
                stderr=(
                    "web-save render start url=https://example.com timeout_ms=30000\n"
                    "web-save fetched url=https://example.com fetch_elapsed_ms=1200"
                ),
            )

        monkeypatch.setattr(subprocess, "run", fake_run)

        with caplog.at_level("WARNING"):
            result = await executor.execute("test-skill", "echo.py", ["hello"])

        assert result["success"] is False
        assert "timeout" in result["error"].lower()
        assert "partial stderr" in caplog.text
        assert "web-save render start" in caplog.text
        assert "partial stdout" in caplog.text

    @pytest.mark.asyncio
    async def test_env_override_timeout_controls_subprocess_timeout(
        self, executor, monkeypatch
    ):
        """Per-call timeout overrides should affect the parent subprocess timeout."""
        captured: dict[str, object] = {}

        def fake_run(*args, **kwargs):
            captured["timeout"] = kwargs["timeout"]
            return subprocess.CompletedProcess(
                args=["python", "echo.py"],
                returncode=0,
                stdout=json.dumps({"success": True, "data": {"message": "ok"}}),
                stderr="",
            )

        monkeypatch.setattr(subprocess, "run", fake_run)

        result = await executor.execute(
            "test-skill",
            "echo.py",
            ["hello"],
            env_overrides={"SKILL_TIMEOUT_SECONDS": "120"},
        )

        assert result["success"] is True
        assert captured["timeout"] == 120

    @pytest.mark.asyncio
    async def test_output_size_limits(self, executor, temp_skills_dir):
        """Should enforce output size limits."""
        # Create a script that produces huge output
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        huge_script = test_skill / "huge.py"
        huge_script.write_text("""#!/usr/bin/env python3
import json
# Generate huge output (> 10MB)
data = "x" * (11 * 1024 * 1024)  # 11MB
print(json.dumps({"success": True, "data": data}))
""")

        result = await executor.execute("test-skill", "huge.py", [])
        assert result["success"] is False
        assert "exceeded limit" in result["error"]

    @pytest.mark.asyncio
    async def test_concurrency_limits(self, executor, temp_skills_dir):
        """Should enforce concurrency limits."""
        # Create a script that takes some time
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        delay_script = test_skill / "delay.py"
        delay_script.write_text("""#!/usr/bin/env python3
import time
import json
time.sleep(0.5)
print(json.dumps({"success": True}))
""")

        # Set low concurrency limit
        original_limit = settings.skill_max_concurrent
        settings.skill_max_concurrent = 2

        try:
            # Launch more tasks than the limit
            tasks = [executor.execute("test-skill", "delay.py", []) for _ in range(5)]

            # All should complete, but only 2 should run concurrently
            results = await asyncio.gather(*tasks)
            assert all(r["success"] is True for r in results)
        finally:
            settings.skill_max_concurrent = original_limit


class TestSkillExecutorExecution:
    """Test script execution functionality."""

    @pytest.mark.asyncio
    async def test_execute_does_not_block_event_loop(self, executor, monkeypatch):
        """Long-running script execution should not block unrelated loop callbacks."""
        callback_fired = threading.Event()
        callback_seen_during_run: list[bool] = []
        to_thread_called = False

        def fake_run(*args, **kwargs):
            del args, kwargs
            callback_seen_during_run.append(callback_fired.is_set())
            return subprocess.CompletedProcess(
                args=["python", "echo.py"],
                returncode=0,
                stdout=json.dumps({"success": True, "data": {"message": "ok"}}),
                stderr="",
            )

        monkeypatch.setattr(subprocess, "run", fake_run)

        async def fake_to_thread(func, *args, **kwargs):
            nonlocal to_thread_called
            to_thread_called = True
            await asyncio.sleep(0)
            return func(*args, **kwargs)

        monkeypatch.setattr(
            "api.services.agent.skills.executor.asyncio.to_thread",
            fake_to_thread,
        )

        loop = asyncio.get_running_loop()
        loop.call_soon(callback_fired.set)

        result = await executor.execute("test-skill", "echo.py", ["hello"])

        assert result["success"] is True
        assert to_thread_called is True
        assert callback_seen_during_run == [True]

    @pytest.mark.asyncio
    async def test_passes_arguments_correctly(self, executor):
        """Should pass arguments to script correctly."""
        result = await executor.execute("test-skill", "echo.py", ["test message"])
        assert result["data"]["message"] == "test message"

    @pytest.mark.asyncio
    async def test_sets_workspace_environment(
        self, executor, temp_workspace, temp_skills_dir
    ):
        """Should set WORKSPACE_BASE environment variable."""
        # Create a script that checks the environment
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        env_script = test_skill / "check_env.py"
        env_script.write_text("""#!/usr/bin/env python3
import os
import json
workspace = os.getenv("WORKSPACE_BASE")
print(json.dumps({"success": True, "data": {"workspace": workspace}}))
""")

        result = await executor.execute("test-skill", "check_env.py", [])
        assert result["success"] is True
        assert result["data"]["workspace"] == str(temp_workspace)

    @pytest.mark.asyncio
    async def test_handles_script_errors(self, executor, temp_skills_dir):
        """Should handle script errors gracefully."""
        # Create a script that fails
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        error_script = test_skill / "error.py"
        error_script.write_text("""#!/usr/bin/env python3
import sys
import json
print(json.dumps({"success": False, "error": "Something went wrong"}), file=sys.stderr)
sys.exit(1)
""")

        result = await executor.execute("test-skill", "error.py", [])
        assert result["success"] is False
        assert "Something went wrong" in result["error"]

    @pytest.mark.asyncio
    async def test_failed_script_cannot_override_success_flag(
        self, executor, temp_skills_dir
    ):
        """Non-zero exits must always normalize to success=False."""
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        bad_success_script = test_skill / "bad_success.py"
        bad_success_script.write_text("""#!/usr/bin/env python3
import json
import sys
print(json.dumps({"success": True, "error": "Should still fail"}), file=sys.stderr)
sys.exit(1)
""")

        result = await executor.execute("test-skill", "bad_success.py", [])
        assert result["success"] is False
        assert result["error"] == "Should still fail"

    @pytest.mark.asyncio
    async def test_failed_script_without_error_gets_fallback_message(
        self, executor, temp_skills_dir
    ):
        """Failure payloads without error text should still include an error message."""
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        missing_error_script = test_skill / "missing_error.py"
        missing_error_script.write_text("""#!/usr/bin/env python3
import json
import sys
print(json.dumps({"status": "failed"}), file=sys.stderr)
sys.exit(1)
""")

        result = await executor.execute("test-skill", "missing_error.py", [])
        assert result["success"] is False
        assert result["error"] == '{"status": "failed"}'

    @pytest.mark.asyncio
    async def test_parses_json_error_after_warning_preamble(
        self, executor, temp_skills_dir
    ):
        """Should recover JSON error payloads from mixed stderr output."""
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        noisy_error_script = test_skill / "noisy_error.py"
        noisy_error_script.write_text("""#!/usr/bin/env python3
import json
import sys
sys.stderr.write("RequestsDependencyWarning: dependency mismatch\\n")
print(json.dumps({
    "success": False,
    "error": {
        "type": "FetchError",
        "message": "Failed to fetch content from Jina.ai: 402 Client Error: Payment Required",
    },
}), file=sys.stderr)
sys.exit(1)
""")

        result = await executor.execute("test-skill", "noisy_error.py", [])
        assert result["success"] is False
        assert isinstance(result["error"], dict)
        assert result["error"]["type"] == "FetchError"
        assert "402 Client Error" in result["error"]["message"]

    @pytest.mark.asyncio
    async def test_no_shell_injection(self, executor, temp_skills_dir):
        """Should prevent shell injection attacks."""
        # Create a script that would be vulnerable if shell=True
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        injection_test = test_skill / "injection.py"
        injection_test.write_text("""#!/usr/bin/env python3
import sys
import json
# If this receives shell metacharacters, it should treat them as literal
message = sys.argv[1] if len(sys.argv) > 1 else ""
print(json.dumps({"success": True, "data": {"message": message}}))
""")

        # Try to inject shell commands
        malicious_input = "; rm -rf / #"
        result = await executor.execute("test-skill", "injection.py", [malicious_input])

        # Should succeed and treat input as literal string
        assert result["success"] is True
        assert result["data"]["message"] == malicious_input

    @pytest.mark.asyncio
    async def test_execute_marks_structured_validation_failure_as_expected_audit_event(
        self,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        """Expected validation failures should not be audited as unexpected errors."""
        skills_dir = tmp_path / "skills"
        script_dir = skills_dir / "web-save" / "scripts"
        script_dir.mkdir(parents=True)
        (script_dir / "save_url.py").write_text("print('placeholder')\n")

        workspace_base = tmp_path / "workspace"
        executor = SkillExecutor(skills_dir=skills_dir, workspace_base=workspace_base)

        stderr_payload = json.dumps(
            {
                "success": False,
                "error": {
                    "type": "ValidationError",
                    "message": (
                        "Reserved placeholder URLs are not supported for website saves."
                    ),
                    "code": "WEB_SAVE_VALIDATION_ERROR",
                },
            }
        )

        async def fake_to_thread(func, *args, **kwargs):
            del func, args, kwargs
            return SimpleNamespace(returncode=1, stdout="", stderr=stderr_payload)

        captured: dict[str, object] = {}

        monkeypatch.setattr(
            "api.services.agent.skills.executor.asyncio.to_thread", fake_to_thread
        )
        monkeypatch.setattr(
            "api.services.agent.skills.executor.AuditLogger.log_tool_call",
            lambda **kwargs: captured.update(kwargs),
        )

        result = await executor.execute(
            "web-save",
            "save_url.py",
            ["https://example.com/articles/123"],
            user_id="user-1",
        )

        assert result["success"] is False
        assert captured["tool_name"] == "web-save.save_url.py"
        assert captured["success"] is False
        assert captured["expected_failure"] is True
        assert captured["error_code"] == "WEB_SAVE_VALIDATION_ERROR"
