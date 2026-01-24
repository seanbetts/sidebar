"""Parameter builders for tasks tools."""

from __future__ import annotations

from api.services.tools.parameter_builders.base import BaseParameterBuilder


class TasksParameterBuilder(BaseParameterBuilder):
    """Builders for tasks tool arguments."""

    @staticmethod
    def build_list_args(params: dict) -> list:
        """Build CLI arguments for list tasks."""
        args = [params["scope"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_search_args(params: dict) -> list:
        """Build CLI arguments for search tasks."""
        args = [params["query"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_create_args(params: dict) -> list:
        """Build CLI arguments for create task."""
        args = [params["title"]]
        TasksParameterBuilder.append_user_id(args, params)

        if params.get("notes"):
            args.extend(["--notes", params["notes"]])
        if params.get("due_date"):
            args.extend(["--due-date", params["due_date"]])
        if params.get("project_id"):
            args.extend(["--project-id", params["project_id"]])
        elif params.get("group_id"):
            args.extend(["--group-id", params["group_id"]])

        return args

    @staticmethod
    def build_complete_args(params: dict) -> list:
        """Build CLI arguments for complete task."""
        args = [params["task_id"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_defer_args(params: dict) -> list:
        """Build CLI arguments for defer task."""
        args = [params["task_id"], params["due_date"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_clear_due_args(params: dict) -> list:
        """Build CLI arguments for clear due date."""
        args = [params["task_id"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_create_project_args(params: dict) -> list:
        """Build CLI arguments for create project."""
        args = [params["title"]]
        TasksParameterBuilder.append_user_id(args, params)

        if params.get("group_id"):
            args.extend(["--group-id", params["group_id"]])

        return args

    @staticmethod
    def build_create_group_args(params: dict) -> list:
        """Build CLI arguments for create group."""
        args = [params["title"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_trash_args(params: dict) -> list:
        """Build CLI arguments for trash task."""
        args = [params["task_id"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_delete_project_args(params: dict) -> list:
        """Build CLI arguments for delete project."""
        args = [params["project_id"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args

    @staticmethod
    def build_delete_group_args(params: dict) -> list:
        """Build CLI arguments for delete group."""
        args = [params["group_id"]]
        TasksParameterBuilder.append_user_id(args, params)
        return args
