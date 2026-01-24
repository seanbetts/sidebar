# Tasks Skill

Manage user tasks including creating, completing, deferring, and organizing tasks into projects and groups.

## Tools

### List Tasks
Fetch tasks by scope (today, upcoming, inbox) with associated projects and groups.

### Search Tasks
Search tasks by title or notes content.

### Create Task
Add a new task with optional due date, project, and notes.

### Complete Task
Mark a task as completed. For repeating tasks, creates the next instance.

### Defer Task
Change a task's due date.

### Clear Due Date
Remove a task's due date.

### Create Project
Create a new project, optionally within a group.

### Create Group
Create a new group for organizing projects.

## Usage

Tasks are organized in a hierarchy:
- **Groups** contain projects and standalone tasks
- **Projects** contain tasks
- **Tasks** can have due dates and recurrence rules

Scopes for listing:
- `today` - Tasks due today or overdue
- `upcoming` - Tasks due in the future
- `inbox` - Unprocessed tasks
