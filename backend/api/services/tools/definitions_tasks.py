"""Tasks tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_tasks_definitions() -> dict:
    """Return tasks tool definitions."""
    return {
        "List Tasks": {
            "description": (
                "Fetch tasks by scope. Use 'today' for tasks due today or overdue, "
                "'upcoming' for future tasks, or 'inbox' for unprocessed tasks. "
                "Returns tasks along with available projects and groups."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "scope": {
                        "type": "string",
                        "enum": ["today", "upcoming", "inbox"],
                        "description": "Which task list to fetch",
                    },
                },
                "required": ["scope"],
            },
            "skill": "tasks",
            "script": "list_tasks.py",
            "build_args": pm.build_tasks_list_args,
        },
        "Search Tasks": {
            "description": (
                "Search tasks by title or notes content. "
                "Returns matching tasks across all projects and groups."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query",
                    },
                },
                "required": ["query"],
            },
            "skill": "tasks",
            "script": "search_tasks.py",
            "build_args": pm.build_tasks_search_args,
        },
        "Create Task": {
            "description": (
                "Create a new task. Optionally set a due date, add to a project, "
                "or include notes. Tasks without a due date go to the inbox."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Task title",
                    },
                    "notes": {
                        "type": "string",
                        "description": "Optional task notes (markdown supported)",
                    },
                    "due_date": {
                        "type": "string",
                        "description": "Due date in ISO format (YYYY-MM-DD)",
                    },
                    "project_id": {
                        "type": "string",
                        "description": "Project ID to add task to",
                    },
                    "group_id": {
                        "type": "string",
                        "description": "Group ID to add task to (if not using project)",
                    },
                },
                "required": ["title"],
            },
            "skill": "tasks",
            "script": "create_task.py",
            "build_args": pm.build_tasks_create_args,
        },
        "Complete Task": {
            "description": (
                "Mark a task as completed. For repeating tasks, this creates "
                "the next instance automatically and returns it."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID to complete",
                    },
                },
                "required": ["task_id"],
            },
            "skill": "tasks",
            "script": "complete_task.py",
            "build_args": pm.build_tasks_complete_args,
        },
        "Defer Task": {
            "description": (
                "Change a task's due date. Use this to reschedule a task "
                "to a different day."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID to defer",
                    },
                    "due_date": {
                        "type": "string",
                        "description": "New due date in ISO format (YYYY-MM-DD)",
                    },
                },
                "required": ["task_id", "due_date"],
            },
            "skill": "tasks",
            "script": "defer_task.py",
            "build_args": pm.build_tasks_defer_args,
        },
        "Clear Task Due Date": {
            "description": (
                "Remove a task's due date. The task will no longer appear "
                "in today or upcoming lists."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID",
                    },
                },
                "required": ["task_id"],
            },
            "skill": "tasks",
            "script": "clear_due_date.py",
            "build_args": pm.build_tasks_clear_due_args,
        },
        "Create Project": {
            "description": (
                "Create a new project for organizing tasks. "
                "Optionally place it within a group."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Project title",
                    },
                    "group_id": {
                        "type": "string",
                        "description": "Optional group ID to add project to",
                    },
                },
                "required": ["title"],
            },
            "skill": "tasks",
            "script": "create_project.py",
            "build_args": pm.build_tasks_create_project_args,
        },
        "Create Group": {
            "description": (
                "Create a new group for organizing projects and tasks. "
                "Groups are top-level containers in the task hierarchy."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "title": {
                        "type": "string",
                        "description": "Group title",
                    },
                },
                "required": ["title"],
            },
            "skill": "tasks",
            "script": "create_group.py",
            "build_args": pm.build_tasks_create_group_args,
        },
    }
