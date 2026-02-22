"""Parameter builders for skills tooling."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class SkillsParameterBuilder(BaseParameterBuilder):
    """Builders for skill tooling arguments."""

    @staticmethod
    def build_assistant_identity_get_args(params: dict) -> list:
        """Build CLI arguments for assistant identity read."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_assistant_identity_update_args(params: dict) -> list:
        """Build CLI arguments for assistant identity updates."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)

        for field_name in ("name", "tone", "values", "boundaries"):
            if field_name in params and params[field_name] is not None:
                args.extend([f"--{field_name}", params[field_name]])
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_assistant_identity_reset_args(params: dict) -> list:
        """Build CLI arguments for assistant identity reset."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_assistant_soul_get_args(params: dict) -> list:
        """Build CLI arguments for assistant soul read."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_assistant_soul_update_args(params: dict) -> list:
        """Build CLI arguments for assistant soul updates."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        for field_name in (
            "purpose",
            "operating_principles",
            "adaptation_policy",
            "success_signals",
        ):
            if field_name in params and params[field_name] is not None:
                # CLI uses kebab-case flags, while tool schema keys are snake_case.
                args.extend([f"--{field_name.replace('_', '-')}", params[field_name]])
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_assistant_soul_reset_args(params: dict) -> list:
        """Build CLI arguments for assistant soul reset."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        if params.get("reason"):
            args.extend(["--reason", params["reason"]])
        return args

    @staticmethod
    def build_profile_user_settings_get_args(params: dict) -> list:
        """Build CLI arguments for profile/user settings read."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_profile_user_settings_update_args(params: dict) -> list:
        """Build CLI arguments for profile/user settings updates."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)

        field_map = (
            ("communication_style", "--communication-style"),
            ("working_relationship", "--working-relationship"),
            ("name", "--name"),
            ("job_title", "--job-title"),
            ("employer", "--employer"),
            ("date_of_birth", "--date-of-birth"),
            ("gender", "--gender"),
            ("pronouns", "--pronouns"),
            ("location", "--location"),
        )
        for field_name, flag_name in field_map:
            if field_name in params and params[field_name] is not None:
                args.extend([flag_name, str(params[field_name])])

        if bool(params.get("clear_date_of_birth")):
            args.append("--clear-date-of-birth")

        return args

    @staticmethod
    def build_profile_image_upload_args(params: dict) -> list:
        """Build CLI arguments for profile image upload."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        if "path" in params and params["path"] is not None:
            args.extend(["--path", str(params["path"])])
        if params.get("content_type"):
            args.extend(["--content-type", str(params["content_type"])])
        return args

    @staticmethod
    def build_profile_image_delete_args(params: dict) -> list:
        """Build CLI arguments for profile image delete."""
        args: list[str] = []
        SkillsParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_submit_bug_report_args(params: dict) -> list:
        """Build CLI arguments for bug report submissions."""
        return SkillsParameterBuilder._build_submit_feedback_args(params, "bug")

    @staticmethod
    def build_submit_feature_request_args(params: dict) -> list:
        """Build CLI arguments for feature request submissions."""
        return SkillsParameterBuilder._build_submit_feedback_args(params, "feature")

    @staticmethod
    def _build_submit_feedback_args(params: dict, issue_kind: str) -> list:
        """Build shared CLI arguments for feedback issue submissions."""
        args: list[str] = ["--kind", issue_kind]
        SkillsParameterBuilder.append_user_id(args, params)

        field_map = (
            ("summary", "--summary"),
            ("details", "--details"),
            ("user_agent", "--user-agent"),
            ("conversation_id", "--conversation-id"),
            ("user_message_id", "--user-message-id"),
            ("assistant_message_id", "--assistant-message-id"),
        )
        for field_name, flag_name in field_map:
            value = params.get(field_name)
            if value is not None:
                trimmed_value = str(value).strip()
                if trimmed_value:
                    args.extend([flag_name, trimmed_value])
        return args
