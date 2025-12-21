"""Execute skill scripts with security hardening and resource limits."""
import subprocess
import json
import os
import asyncio
import time
from pathlib import Path
from typing import Dict, Any, List
from api.config import settings
from api.security.audit_logger import AuditLogger


class SkillExecutor:
    """
    Execute skill scripts with security hardening and resource limits.

    Security measures:
    - Validates script paths to prevent path traversal
    - Restricts execution to skills directory
    - Validates workspace paths to prevent escaping
    - Limits execution time (configurable timeout)
    - Minimal environment variables
    - No shell=True (prevents command injection)

    Resource limits:
    - Concurrency control (max N concurrent executions)
    - Output size limits (prevent memory blow-ups)
    - Audit logging for all executions
    """

    def __init__(self, skills_dir: Path, workspace_base: Path):
        self.skills_dir = skills_dir.resolve()
        self.workspace_base = workspace_base.resolve()

        # Concurrency control
        self._semaphore = asyncio.Semaphore(settings.skill_max_concurrent)

        # Whitelist of allowed skills (add as needed)
        self.allowed_skills = {
            "fs", "notes", "web-save", "youtube-download",
            "youtube-transcribe", "audio-transcribe"
        }

    def _validate_script_path(self, skill_name: str, script_name: str) -> Path:
        """Validate script path is within skills directory."""
        # Check skill is whitelisted
        if skill_name not in self.allowed_skills:
            raise ValueError(f"Skill not allowed: {skill_name}")

        # Construct path
        script_path = (self.skills_dir / skill_name / "scripts" / script_name).resolve()

        # Validate path is within skills directory
        try:
            script_path.relative_to(self.skills_dir)
        except ValueError:
            raise ValueError(f"Script path outside skills directory: {script_path}")

        # Validate file exists and is a Python file
        if not script_path.exists():
            raise FileNotFoundError(f"Script not found: {skill_name}/{script_name}")

        if script_path.suffix != ".py":
            raise ValueError(f"Only Python scripts allowed: {script_name}")

        return script_path

    def _validate_workspace_paths(self, args: List[str]) -> None:
        """Validate that any file paths in args are within workspace."""
        # This is a basic check - scripts should also validate paths
        for arg in args:
            if arg.startswith("/") or ".." in arg:
                # Check if it's an absolute path pointing to workspace
                try:
                    path = Path(arg).resolve()
                    # Allow if within workspace
                    path.relative_to(self.workspace_base)
                except (ValueError, RuntimeError):
                    # Path traversal attempt or outside workspace
                    if ".." in arg:
                        raise ValueError(f"Path traversal not allowed: {arg}")

    async def execute(
        self,
        skill_name: str,
        script_name: str,
        args: List[str],
        user_id: str = None
    ) -> Dict[str, Any]:
        """Execute skill script with resource limits and audit logging."""
        start_time = time.time()

        # Acquire semaphore for concurrency control
        async with self._semaphore:
            try:
                # Validate script path
                script_path = self._validate_script_path(skill_name, script_name)

                # Validate workspace paths
                self._validate_workspace_paths(args)

                # Build command (no shell=True to prevent injection)
                cmd = ["python", str(script_path)] + args + ["--json"]

                # Minimal environment - only what's needed
                env = {
                    "WORKSPACE_BASE": str(self.workspace_base),
                    "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
                    "PYTHONPATH": os.environ.get("PYTHONPATH", ""),
                }

                # Add Doppler token if present (for skills that need secrets)
                if "DOPPLER_TOKEN" in os.environ:
                    env["DOPPLER_TOKEN"] = os.environ["DOPPLER_TOKEN"]

                # Execute with strict timeout and no shell
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    env=env,
                    timeout=settings.skill_timeout_seconds,
                    shell=False,  # Explicit: never use shell
                    cwd=self.workspace_base  # Run in workspace (not skills dir)
                )

                # Enforce output size limits
                stdout_bytes = len(result.stdout.encode('utf-8'))
                stderr_bytes = len(result.stderr.encode('utf-8'))

                if stdout_bytes > settings.skill_max_output_bytes:
                    raise ValueError(
                        f"stdout exceeded limit: {stdout_bytes} > {settings.skill_max_output_bytes}"
                    )

                if stderr_bytes > settings.skill_max_output_bytes:
                    raise ValueError(
                        f"stderr exceeded limit: {stderr_bytes} > {settings.skill_max_output_bytes}"
                    )

                duration_ms = (time.time() - start_time) * 1000

                if result.returncode == 0:
                    output = json.loads(result.stdout)
                    # Audit log success
                    AuditLogger.log_tool_call(
                        tool_name=f"{skill_name}.{script_name}",
                        parameters={"args": args},
                        duration_ms=duration_ms,
                        success=True,
                        user_id=user_id
                    )
                    return output
                else:
                    try:
                        error = json.loads(result.stderr)
                    except:
                        error = {"error": result.stderr}

                    # Audit log failure
                    AuditLogger.log_tool_call(
                        tool_name=f"{skill_name}.{script_name}",
                        parameters={"args": args},
                        duration_ms=duration_ms,
                        success=False,
                        error=error.get("error", "Unknown error"),
                        user_id=user_id
                    )
                    return {"success": False, **error}

            except subprocess.TimeoutExpired:
                duration_ms = (time.time() - start_time) * 1000
                error_msg = f"Script execution timeout ({settings.skill_timeout_seconds}s)"
                AuditLogger.log_tool_call(
                    tool_name=f"{skill_name}.{script_name}",
                    parameters={"args": args},
                    duration_ms=duration_ms,
                    success=False,
                    error=error_msg,
                    user_id=user_id
                )
                return {"success": False, "error": error_msg}
            except (ValueError, FileNotFoundError) as e:
                duration_ms = (time.time() - start_time) * 1000
                AuditLogger.log_tool_call(
                    tool_name=f"{skill_name}.{script_name}",
                    parameters={"args": args},
                    duration_ms=duration_ms,
                    success=False,
                    error=str(e),
                    user_id=user_id
                )
                return {"success": False, "error": str(e)}
            except Exception as e:
                duration_ms = (time.time() - start_time) * 1000
                error_msg = f"Unexpected error: {str(e)}"
                AuditLogger.log_tool_call(
                    tool_name=f"{skill_name}.{script_name}",
                    parameters={"args": args},
                    duration_ms=duration_ms,
                    success=False,
                    error=error_msg,
                    user_id=user_id
                )
                return {"success": False, "error": error_msg}
