import Foundation

struct TaskListOption: Identifiable {
    let id: String
    let label: String
}

func buildListOptions(groups: [TaskGroup], projects: [TaskProject]) -> [TaskListOption] {
    let sortedGroups = groups.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    let projectsByGroup = Dictionary(grouping: projects, by: { $0.groupId ?? "" })
    var options: [TaskListOption] = []

    for group in sortedGroups {
        options.append(TaskListOption(id: group.id, label: group.title))
        let groupProjects = (projectsByGroup[group.id] ?? []).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        for project in groupProjects {
            options.append(TaskListOption(id: project.id, label: "- \(project.title)"))
        }
    }

    let orphanProjects = (projectsByGroup[""] ?? []).sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    for project in orphanProjects {
        options.append(TaskListOption(id: project.id, label: "- \(project.title)"))
    }

    return options
}
