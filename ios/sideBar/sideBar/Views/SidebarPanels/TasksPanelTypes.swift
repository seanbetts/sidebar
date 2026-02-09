struct TaskListTarget {
    let id: String
    let title: String
    let kind: TaskListTargetKind
}

enum TaskListTargetKind {
    case group
    case project
}
