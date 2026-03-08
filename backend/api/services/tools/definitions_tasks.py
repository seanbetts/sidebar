"""Tasks tool definitions."""

from __future__ import annotations

from api.services.tools import parameter_mapper as pm


def get_tasks_definitions() -> dict:
    """Return tasks tool definitions."""
    return {
        "List Tasks": {
            "description": (
                "Fetch tasks by scope. Use 'today' for tasks due today, overdue, "
                "or unscheduled, and 'upcoming' for future tasks. "
                "Returns tasks along with available projects and groups."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "scope": {
                        "type": "string",
                        "enum": ["today", "upcoming", "completed"],
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
                "or include notes. Tasks without a due date remain available in "
                "their group or project views."
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
        "Rename Task": {
            "description": "Rename a task title by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID to rename",
                    },
                    "new_name": {
                        "type": "string",
                        "description": "New task title",
                    },
                },
                "required": ["task_id", "new_name"],
            },
            "skill": "tasks",
            "script": "rename_task.py",
            "build_args": pm.build_tasks_rename_args,
        },
        "Update Task Notes": {
            "description": (
                "Update task notes by ID. Pass an empty string to clear notes."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID to update",
                    },
                    "notes": {
                        "type": "string",
                        "description": "New notes content (markdown/plain text)",
                    },
                },
                "required": ["task_id", "notes"],
            },
            "skill": "tasks",
            "script": "update_task_notes.py",
            "build_args": pm.build_tasks_update_notes_args,
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
        "Set Task Due Date": {
            "description": (
                "Set a task due date to a specific day in ISO format (YYYY-MM-DD)."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID",
                    },
                    "due_date": {
                        "type": "string",
                        "description": "Due date in ISO format (YYYY-MM-DD)",
                    },
                },
                "required": ["task_id", "due_date"],
            },
            "skill": "tasks",
            "script": "set_due_date.py",
            "build_args": pm.build_tasks_set_due_args,
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
        "Set Task Repeat": {
            "description": (
                "Set or clear a task repeat rule. Provide recurrence_rule as an object "
                "to enable repeating, or null to remove repeating."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID",
                    },
                    "recurrence_rule": {
                        "type": ["object", "null"],
                        "description": (
                            "Repeat rule object with type (daily|weekly|monthly) "
                            "and optional interval/weekday/day_of_month. "
                            "Use null to clear repeating."
                        ),
                    },
                    "start_date": {
                        "type": "string",
                        "description": (
                            "Optional anchor date in ISO format (YYYY-MM-DD). "
                            "If omitted, current task deadline is used when available."
                        ),
                    },
                },
                "required": ["task_id", "recurrence_rule"],
            },
            "skill": "tasks",
            "script": "set_task_repeat.py",
            "build_args": pm.build_tasks_set_repeat_args,
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
        "Rename Project": {
            "description": "Rename a task project title by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "project_id": {
                        "type": "string",
                        "description": "Project ID to rename",
                    },
                    "new_name": {
                        "type": "string",
                        "description": "New project title",
                    },
                },
                "required": ["project_id", "new_name"],
            },
            "skill": "tasks",
            "script": "rename_project.py",
            "build_args": pm.build_tasks_rename_project_args,
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
        "Rename Group": {
            "description": "Rename a task group title by ID.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "group_id": {
                        "type": "string",
                        "description": "Group ID to rename",
                    },
                    "new_name": {
                        "type": "string",
                        "description": "New group title",
                    },
                },
                "required": ["group_id", "new_name"],
            },
            "skill": "tasks",
            "script": "rename_group.py",
            "build_args": pm.build_tasks_rename_group_args,
        },
        "Delete Task": {
            "description": (
                "Delete a task. For repeating tasks, this also deletes "
                "all instances in the repeat series."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID to delete",
                    },
                },
                "required": ["task_id"],
            },
            "skill": "tasks",
            "script": "trash_task.py",
            "build_args": pm.build_tasks_trash_args,
        },
        "Delete Project": {
            "description": "Delete a project. Tasks in the project are not deleted.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "project_id": {
                        "type": "string",
                        "description": "Project ID to delete",
                    },
                },
                "required": ["project_id"],
            },
            "skill": "tasks",
            "script": "delete_project.py",
            "build_args": pm.build_tasks_delete_project_args,
        },
        "Delete Group": {
            "description": (
                "Delete a group. Projects and tasks in the group are not deleted."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "group_id": {
                        "type": "string",
                        "description": "Group ID to delete",
                    },
                },
                "required": ["group_id"],
            },
            "skill": "tasks",
            "script": "delete_group.py",
            "build_args": pm.build_tasks_delete_group_args,
        },
        "Move Task": {
            "description": (
                "Move a task to a different project or group. "
                "Provide either a project_id or group_id as the destination."
            ),
            "input_schema": {
                "type": "object",
                "properties": {
                    "task_id": {
                        "type": "string",
                        "description": "Task ID to move",
                    },
                    "project_id": {
                        "type": "string",
                        "description": "Target project ID",
                    },
                    "group_id": {
                        "type": "string",
                        "description": "Target group ID (if not using project)",
                    },
                },
                "required": ["task_id"],
            },
            "skill": "tasks",
            "script": "move_task.py",
            "build_args": pm.build_tasks_move_args,
        },
    }
