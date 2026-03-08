---
name: tasks
description: Create, complete, defer, and organize tasks and projects.
metadata:
  capabilities:
    reads: true
    writes: true
    network: false
    external_apis: false
---

# Tasks Skill

Manage user tasks including creating, completing, deferring, and organizing tasks into projects and groups.

## Tools

### List Tasks
Fetch tasks by scope (`today`, `upcoming`, `completed`) with associated projects and groups.

### Search Tasks
Search tasks by title or notes content.

### Create Task
Add a new task with optional due date, project, and notes.

### Complete Task
Mark a task as completed. For repeating tasks, creates the next instance.

### Rename Task
Rename a task title by ID.

### Update Task Notes
Update or clear a task's notes content.

### Defer Task
Change a task's due date.

### Set Task Due Date
Set a task due date to a specific date.

### Clear Due Date
Remove a task's due date.

### Set Task Repeat
Set or clear recurrence rules for a task.

### Create Project
Create a new project, optionally within a group.

### Rename Project
Rename a project title by ID.

### Create Group
Create a new group for organizing projects.

### Rename Group
Rename a group title by ID.

### Move Task
Move a task to a project or group.

### Delete Task
Delete a task (and repeat instances when applicable).

### Delete Project
Delete a project and its tasks.

### Delete Group
Delete a group and its nested projects/tasks.

## Usage

Tasks are organized in a hierarchy:
- **Groups** contain projects and standalone tasks
- **Projects** contain tasks
- **Tasks** can have due dates and recurrence rules

Scopes for listing:
- `today` - Tasks due today, overdue, or without a due date
- `upcoming` - Tasks due in the future
- `completed` - Completed tasks
