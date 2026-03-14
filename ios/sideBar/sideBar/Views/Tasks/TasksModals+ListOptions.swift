import Foundation

struct TaskListOption: Identifiable {
    let id: String
    let label: String
}

struct MoveTaskDestination: Identifiable, Equatable {
    let id: String
    let label: String
}

struct MoveTaskSection: Identifiable, Equatable {
    let id: String
    let title: String
    let destinations: [MoveTaskDestination]
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
            options.append(TaskListOption(id: project.id, label: project.title))
        }
    }

    let orphanProjects = (projectsByGroup[""] ?? []).sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    for project in orphanProjects {
        options.append(TaskListOption(id: project.id, label: project.title))
    }

    return options
}

func buildMoveTaskSections(groups: [TaskGroup], projects: [TaskProject]) -> [MoveTaskSection] {
    let sortedGroups = groups.sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    let projectsByGroup = Dictionary(grouping: projects, by: { $0.groupId ?? "" })

    let groupSection = MoveTaskSection(
        id: "groups",
        title: "Groups",
        destinations: sortedGroups.map { MoveTaskDestination(id: $0.id, label: $0.title) }
    )

    var projectDestinations: [MoveTaskDestination] = []
    for group in sortedGroups {
        let groupProjects = (projectsByGroup[group.id] ?? []).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        projectDestinations.append(
            contentsOf: groupProjects.map { MoveTaskDestination(id: $0.id, label: $0.title) }
        )
    }

    let orphanProjects = (projectsByGroup[""] ?? []).sorted {
        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
    projectDestinations.append(
        contentsOf: orphanProjects.map { MoveTaskDestination(id: $0.id, label: $0.title) }
    )

    let projectSection = MoveTaskSection(
        id: "projects",
        title: "Projects",
        destinations: projectDestinations
    )

    return [
        MoveTaskSection(
            id: "none",
            title: "No group",
            destinations: [MoveTaskDestination(id: "", label: "No group")]
        ),
        groupSection,
        projectSection
    ]
    .filter { !$0.destinations.isEmpty }
}
