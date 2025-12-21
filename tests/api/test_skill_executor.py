"""Tests for SkillExecutor security and functionality."""
import pytest
import asyncio
from pathlib import Path
from api.executors.skill_executor import SkillExecutor
from api.config import settings


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
    test_script.write_text('''#!/usr/bin/env python3
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
''')

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
        result = await executor.execute(
            "test-skill",
            "echo.py",
            ["../../etc/passwd"]
        )
        assert result["success"] is False
        assert "Path traversal not allowed" in result["error"]

    @pytest.mark.asyncio
    async def test_timeout_enforcement(self, executor, temp_skills_dir):
        """Should enforce execution timeout."""
        # Create a script that sleeps
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        slow_script = test_skill / "slow.py"
        slow_script.write_text('''#!/usr/bin/env python3
import time
import json
time.sleep(60)  # Sleep longer than timeout
print(json.dumps({"success": True}))
''')

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
    async def test_output_size_limits(self, executor, temp_skills_dir):
        """Should enforce output size limits."""
        # Create a script that produces huge output
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        huge_script = test_skill / "huge.py"
        huge_script.write_text('''#!/usr/bin/env python3
import json
# Generate huge output (> 10MB)
data = "x" * (11 * 1024 * 1024)  # 11MB
print(json.dumps({"success": True, "data": data}))
''')

        result = await executor.execute("test-skill", "huge.py", [])
        assert result["success"] is False
        assert "exceeded limit" in result["error"]

    @pytest.mark.asyncio
    async def test_concurrency_limits(self, executor, temp_skills_dir):
        """Should enforce concurrency limits."""
        # Create a script that takes some time
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        delay_script = test_skill / "delay.py"
        delay_script.write_text('''#!/usr/bin/env python3
import time
import json
time.sleep(0.5)
print(json.dumps({"success": True}))
''')

        # Set low concurrency limit
        original_limit = settings.skill_max_concurrent
        settings.skill_max_concurrent = 2

        try:
            # Launch more tasks than the limit
            tasks = [
                executor.execute("test-skill", "delay.py", [])
                for _ in range(5)
            ]

            # All should complete, but only 2 should run concurrently
            results = await asyncio.gather(*tasks)
            assert all(r["success"] is True for r in results)
        finally:
            settings.skill_max_concurrent = original_limit


class TestSkillExecutorExecution:
    """Test script execution functionality."""

    @pytest.mark.asyncio
    async def test_passes_arguments_correctly(self, executor):
        """Should pass arguments to script correctly."""
        result = await executor.execute("test-skill", "echo.py", ["test message"])
        assert result["data"]["message"] == "test message"

    @pytest.mark.asyncio
    async def test_sets_workspace_environment(self, executor, temp_workspace, temp_skills_dir):
        """Should set WORKSPACE_BASE environment variable."""
        # Create a script that checks the environment
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        env_script = test_skill / "check_env.py"
        env_script.write_text('''#!/usr/bin/env python3
import os
import json
workspace = os.getenv("WORKSPACE_BASE")
print(json.dumps({"success": True, "data": {"workspace": workspace}}))
''')

        result = await executor.execute("test-skill", "check_env.py", [])
        assert result["success"] is True
        assert result["data"]["workspace"] == str(temp_workspace)

    @pytest.mark.asyncio
    async def test_handles_script_errors(self, executor, temp_skills_dir):
        """Should handle script errors gracefully."""
        # Create a script that fails
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        error_script = test_skill / "error.py"
        error_script.write_text('''#!/usr/bin/env python3
import sys
import json
print(json.dumps({"success": False, "error": "Something went wrong"}), file=sys.stderr)
sys.exit(1)
''')

        result = await executor.execute("test-skill", "error.py", [])
        assert result["success"] is False
        assert "Something went wrong" in result["error"]

    @pytest.mark.asyncio
    async def test_no_shell_injection(self, executor, temp_skills_dir):
        """Should prevent shell injection attacks."""
        # Create a script that would be vulnerable if shell=True
        test_skill = temp_skills_dir / "test-skill" / "scripts"
        injection_test = test_skill / "injection.py"
        injection_test.write_text('''#!/usr/bin/env python3
import sys
import json
# If this receives shell metacharacters, it should treat them as literal
message = sys.argv[1] if len(sys.argv) > 1 else ""
print(json.dumps({"success": True, "data": {"message": message}}))
''')

        # Try to inject shell commands
        malicious_input = "; rm -rf / #"
        result = await executor.execute("test-skill", "injection.py", [malicious_input])

        # Should succeed and treat input as literal string
        assert result["success"] is True
        assert result["data"]["message"] == malicious_input
