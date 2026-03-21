"""Execute skill scripts with security hardening and resource limits."""

import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from api.config import settings
from api.security.audit_logger import AuditLogger

logger = logging.getLogger(__name__)


class SkillExecutor:
    """Execute skill scripts with security hardening and resource limits.

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
        """Initialize executor with skill and workspace roots.

        Args:
            skills_dir: Base directory for installed skills.
            workspace_base: Base workspace path for tool executions.
        """
        self.skills_dir = skills_dir.resolve()
        self.workspace_base = workspace_base.resolve()
        self.workspace_base.mkdir(parents=True, exist_ok=True)
        (self.workspace_base / "notes").mkdir(parents=True, exist_ok=True)
        (self.workspace_base / "documents").mkdir(parents=True, exist_ok=True)

        # Concurrency control
        self._semaphore = asyncio.Semaphore(settings.skill_max_concurrent)

        # Whitelist of allowed skills (installed skill directories)
        self.allowed_skills = {
            path.name for path in self.skills_dir.iterdir() if path.is_dir()
        }

    def _validate_script_path(self, skill_name: str, script_name: str) -> Path:
        """Validate script path is within skills directory."""
        # Check skill is whitelisted
        if skill_name not in self.allowed_skills:
            raise ValueError(f"Skill not allowed: {skill_name}")

        # Construct path (default scripts/; allow relative paths or root scripts)
        if "/" in script_name or "\\" in script_name:
            script_path = (self.skills_dir / skill_name / script_name).resolve()
        else:
            default_path = (
                self.skills_dir / skill_name / "scripts" / script_name
            ).resolve()
            if default_path.exists():
                script_path = default_path
            else:
                script_path = (self.skills_dir / skill_name / script_name).resolve()

        # Validate path is within skills directory
        try:
            script_path.relative_to(self.skills_dir)
        except ValueError as err:
            raise ValueError(
                f"Script path outside skills directory: {script_path}"
            ) from err

        # Validate file exists and is a Python file
        if not script_path.exists():
            raise FileNotFoundError(f"Script not found: {skill_name}/{script_name}")

        if script_path.suffix != ".py":
            raise ValueError(f"Only Python scripts allowed: {script_name}")

        return script_path

    def _validate_workspace_paths(self, args: list[str]) -> None:
        """Validate that any file paths in args are within workspace."""
        # This is a basic check - scripts should also validate paths
        for arg in args:
            if arg.startswith("/") or ".." in arg:
                # Check if it's an absolute path pointing to workspace
                try:
                    path = Path(arg).resolve()
                    # Allow if within workspace
                    path.relative_to(self.workspace_base)
                except (ValueError, RuntimeError) as err:
                    # Path traversal attempt or outside workspace
                    if ".." in arg:
                        raise ValueError(f"Path traversal not allowed: {arg}") from err

    @staticmethod
    def _extract_json_from_text(text: str) -> dict[str, Any] | None:
        """Extract the trailing JSON object from a mixed stderr blob."""
        stderr = text.strip()
        if not stderr:
            return None

        try:
            parsed = json.loads(stderr)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass

        decoder = json.JSONDecoder()
        brace_indices = [idx for idx, char in enumerate(stderr) if char == "{"]
        for start in reversed(brace_indices):
            candidate = stderr[start:]
            try:
                parsed, end = decoder.raw_decode(candidate)
            except json.JSONDecodeError:
                continue
            if not isinstance(parsed, dict):
                continue
            if candidate[end:].strip():
                continue
            return parsed

        return None

    @classmethod
    def _normalize_failure_payload(cls, stderr_text: str) -> dict[str, Any]:
        """Normalize a failed script stderr payload into API shape."""
        fallback_error = stderr_text.strip() or "Script execution failed"
        parsed = cls._extract_json_from_text(stderr_text)
        payload = parsed if parsed is not None else {}
        if not isinstance(payload, dict):
            payload = {}

        error_value = payload.get("error")
        if isinstance(error_value, str):
            normalized_error = error_value.strip() or fallback_error
        elif error_value is not None:
            normalized_error = error_value
        else:
            message_value = payload.get("message")
            if isinstance(message_value, str) and message_value.strip():
                normalized_error = message_value.strip()
            else:
                normalized_error = fallback_error

        normalized: dict[str, Any] = dict(payload)
        normalized["success"] = False
        normalized["error"] = normalized_error
        return normalized

    @staticmethod
    def _error_summary(error_payload: dict[str, Any]) -> str:
        """Build a concise summary string for audit logging."""
        error_value = error_payload.get("error")
        if isinstance(error_value, dict):
            nested_message = error_value.get("message")
            if isinstance(nested_message, str) and nested_message.strip():
                return nested_message
            return json.dumps(error_value)
        if isinstance(error_value, str):
            return error_value
        return str(error_payload)

    @staticmethod
    def _decode_timeout_stream(stream: bytes | str | None) -> str:
        """Decode partial stdout/stderr captured on subprocess timeout."""
        if stream is None:
            return ""
        if isinstance(stream, bytes):
            return stream.decode("utf-8", errors="replace").strip()
        return stream.strip()

    @staticmethod
    def _resolve_timeout_seconds(env_overrides: dict[str, str] | None) -> int:
        """Return the effective subprocess timeout for a skill execution."""
        if env_overrides:
            raw_timeout = env_overrides.get("SKILL_TIMEOUT_SECONDS")
            if raw_timeout is not None:
                try:
                    timeout_seconds = int(raw_timeout)
                except (TypeError, ValueError):
                    timeout_seconds = settings.skill_timeout_seconds
                else:
                    if timeout_seconds > 0:
                        return timeout_seconds
        return settings.skill_timeout_seconds

    async def execute(
        self,
        skill_name: str,
        script_name: str,
        args: list[str],
        user_id: str | None = None,
        expect_json: bool = True,
        env_overrides: dict[str, str] | None = None,
    ) -> dict[str, Any]:
        """Execute skill script with resource limits and audit logging."""
        start_time = time.time()

        # Acquire semaphore for concurrency control
        async with self._semaphore:
            try:
                timeout_seconds = self._resolve_timeout_seconds(env_overrides)

                # Validate script path
                script_path = self._validate_script_path(skill_name, script_name)

                # Validate workspace paths
                self._validate_workspace_paths(args)

                # Build command (no shell=True to prevent injection)
                cmd = [sys.executable, str(script_path)] + args
                if expect_json and "--json" not in args:
                    cmd.append("--json")

                # Minimal environment - only what's needed
                pythonpath = os.environ.get("PYTHONPATH", "")
                if Path("/app").exists():
                    pythonpath = f"{pythonpath}:/app" if pythonpath else "/app"

                env = {
                    "WORKSPACE_BASE": str(self.workspace_base),
                    "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
                    "PYTHONPATH": pythonpath,
                }

                # Add selected runtime secrets/config if present.
                # Required for DB-backed skills.
                for key in (
                    "DOPPLER_TOKEN",
                    "BEARER_TOKEN",
                    "ANTHROPIC_API_KEY",
                    "DATABASE_URL",
                    "TESTING",
                    "TEST_USER_ID",
                    "SUPABASE_POSTGRES_PSWD",
                    "SUPABASE_PROJECT_ID",
                    "SUPABASE_USE_POOLER",
                    "SUPABASE_POOLER_HOST",
                    "SUPABASE_POOLER_USER",
                    "SUPABASE_DB_NAME",
                    "SUPABASE_DB_PORT",
                    "SUPABASE_DB_USER",
                    "SUPABASE_SSLMODE",
                    "SUPABASE_APP_PSWD",
                    "OPENAI_API_KEY",
                    "GOOGLE_API_KEY",
                    "JINA_API_KEY",
                    "GITHUB_ISSUES_TOKEN",
                    "GITHUB_ISSUES_OWNER",
                    "GITHUB_ISSUES_REPO",
                    "GITHUB_ISSUES_API_BASE",
                    "JINA_SSL_VERIFY",
                    "JINA_CA_BUNDLE",
                    "REQUESTS_CA_BUNDLE",
                    "SSL_CERT_FILE",
                    "R2_ENDPOINT",
                    "R2_BUCKET",
                    "R2_FAVICON_BUCKET",
                    "R2_ACCESS_KEY_ID",
                    "R2_ACCESS_KEY",
                    "R2_SECRET_ACCESS_KEY",
                    "STORAGE_BACKEND",
                ):
                    if key in os.environ:
                        env[key] = os.environ[key]
                if env_overrides:
                    env.update(env_overrides)

                # Execute with strict timeout and no shell
                result = await asyncio.to_thread(
                    subprocess.run,
                    cmd,
                    capture_output=True,
                    text=True,
                    env=env,
                    timeout=timeout_seconds,
                    shell=False,  # Explicit: never use shell
                    cwd=self.workspace_base,  # Run in workspace (not skills dir)
                )

                # Enforce output size limits
                stdout_bytes = len(result.stdout.encode("utf-8"))
                stderr_bytes = len(result.stderr.encode("utf-8"))

                if stdout_bytes > settings.skill_max_output_bytes:
                    raise ValueError(
                        "stdout exceeded limit: "
                        f"{stdout_bytes} > {settings.skill_max_output_bytes}"
                    )

                if stderr_bytes > settings.skill_max_output_bytes:
                    raise ValueError(
                        "stderr exceeded limit: "
                        f"{stderr_bytes} > {settings.skill_max_output_bytes}"
                    )

                duration_ms = (time.time() - start_time) * 1000

                if result.returncode == 0:
                    if expect_json:
                        output = json.loads(result.stdout)
                    else:
                        output = {
                            "success": True,
                            "data": {
                                "stdout": result.stdout,
                                "stderr": result.stderr,
                            },
                        }
                    stderr_text = result.stderr.strip()
                    if stderr_text:
                        logger.info(
                            "Skill %s/%s stderr: %s",
                            skill_name,
                            script_name,
                            stderr_text[:2000],
                        )
                    # Audit log success
                    AuditLogger.log_tool_call(
                        tool_name=f"{skill_name}.{script_name}",
                        parameters={"args": args},
                        duration_ms=duration_ms,
                        success=True,
                        user_id=user_id,
                    )
                    return output
                else:
                    error = self._normalize_failure_payload(result.stderr)

                    # Audit log failure
                    AuditLogger.log_tool_call(
                        tool_name=f"{skill_name}.{script_name}",
                        parameters={"args": args},
                        duration_ms=duration_ms,
                        success=False,
                        error=self._error_summary(error),
                        user_id=user_id,
                    )
                    return error

            except subprocess.TimeoutExpired as exc:
                duration_ms = (time.time() - start_time) * 1000
                error_msg = f"Script execution timeout ({timeout_seconds}s)"
                stderr_text = self._decode_timeout_stream(exc.stderr)
                stdout_text = self._decode_timeout_stream(exc.output)
                if stderr_text:
                    logger.warning(
                        "Skill %s/%s partial stderr before timeout: %s",
                        skill_name,
                        script_name,
                        stderr_text[:2000],
                    )
                if stdout_text:
                    logger.warning(
                        "Skill %s/%s partial stdout before timeout: %s",
                        skill_name,
                        script_name,
                        stdout_text[:2000],
                    )
                AuditLogger.log_tool_call(
                    tool_name=f"{skill_name}.{script_name}",
                    parameters={"args": args},
                    duration_ms=duration_ms,
                    success=False,
                    error=error_msg,
                    user_id=user_id,
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
                    user_id=user_id,
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
                    user_id=user_id,
                )
                return {"success": False, "error": error_msg}
