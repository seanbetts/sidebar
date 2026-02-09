import Foundation
import sideBarShared

extension TasksUtils {
    public static func buildTodaySections(
        tasks: [TaskItem],
        groups: [TaskGroup],
        projects: [TaskProject],
        groupTitleById: [String: String],
        projectTitleById: [String: String]
    ) -> [TaskSection] {
        var buckets = buildGroupBuckets(groups)
        for task in tasks {
            appendTaskToTodayBuckets(
                task,
                buckets: &buckets,
                projects: projects,
                groupTitleById: groupTitleById,
                projectTitleById: projectTitleById
            )
        }

        for key in buckets.keys {
            if var section = buckets[key] {
                section.tasks = sortByDueDate(section.tasks)
                buckets[key] = section
            }
        }

        return orderedTodaySections(from: buckets, groups: groups)
    }

    public static func buildSearchSections(tasks: [TaskItem], groups: [TaskGroup]) -> [TaskSection] {
        var sections: [TaskSection] = []
        var tasksByGroup: [String: [TaskItem]] = [:]
        var unassigned: [TaskItem] = []

        for group in groups {
            tasksByGroup[group.id] = []
        }

        for task in tasks {
            if let groupId = task.groupId, tasksByGroup[groupId] != nil {
                tasksByGroup[groupId]?.append(task)
            } else {
                unassigned.append(task)
            }
        }

        for group in groups {
            let bucket = tasksByGroup[group.id] ?? []
            if !bucket.isEmpty {
                sections.append(TaskSection(id: group.id, title: group.title, tasks: sortByDueDate(bucket)))
            }
        }

        if !unassigned.isEmpty {
            sections.append(TaskSection(id: "other", title: "Other", tasks: sortByDueDate(unassigned)))
        }

        return sections
    }

    public static func buildGroupSections(
        tasks: [TaskItem],
        groupId: String,
        groupTitle: String,
        projects: [TaskProject]
    ) -> [TaskSection] {
        let projectsInGroup = projects.filter { $0.groupId == groupId }
        let projectById = Dictionary(uniqueKeysWithValues: projectsInGroup.map { ($0.id, $0) })
        var projectSections: [String: [TaskItem]] = [:]
        var groupTasks: [TaskItem] = []

        for task in tasks {
            if let projectId = task.projectId, projectById[projectId] != nil {
                projectSections[projectId, default: []].append(task)
                continue
            }
            if task.groupId == groupId || task.projectId == nil {
                groupTasks.append(task)
            }
        }

        var sections: [TaskSection] = []
        if !groupTasks.isEmpty {
            sections.append(TaskSection(id: "group", title: groupTitle, tasks: groupTasks))
        }

        for project in projectsInGroup.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            if let bucket = projectSections[project.id], !bucket.isEmpty {
                sections.append(TaskSection(id: project.id, title: project.title, tasks: bucket))
            }
        }

        return sections
    }

    private static func buildGroupBuckets(_ groups: [TaskGroup]) -> [String: TaskSection] {
        var buckets: [String: TaskSection] = [:]
        for group in groups {
            buckets["group:\(group.id)"] = TaskSection(id: group.id, title: group.title, tasks: [])
        }
        return buckets
    }

    private static func appendTaskToTodayBuckets(
        _ task: TaskItem,
        buckets: inout [String: TaskSection],
        projects: [TaskProject],
        groupTitleById: [String: String],
        projectTitleById: [String: String]
    ) {
        if let groupId = resolvedGroupId(for: task, projects: projects) {
            let key = "group:\(groupId)"
            let title = groupTitleById[groupId] ?? "Group"
            appendTask(task, buckets: &buckets, key: key, title: title)
            return
        }
        if let projectId = task.projectId {
            let key = "project:\(projectId)"
            let title = projectTitleById[projectId] ?? "Project"
            appendTask(task, buckets: &buckets, key: key, title: title)
            return
        }
        appendTask(task, buckets: &buckets, key: "other", title: "Other")
    }

    private static func resolvedGroupId(for task: TaskItem, projects: [TaskProject]) -> String? {
        if let groupId = task.groupId {
            return groupId
        }
        guard let projectId = task.projectId else {
            return nil
        }
        return projects.first(where: { $0.id == projectId })?.groupId
    }

    private static func appendTask(
        _ task: TaskItem,
        buckets: inout [String: TaskSection],
        key: String,
        title: String
    ) {
        var section = buckets[key] ?? TaskSection(id: key, title: title, tasks: [])
        section.tasks.append(task)
        buckets[key] = section
    }

    private static func orderedTodaySections(
        from buckets: [String: TaskSection],
        groups: [TaskGroup]
    ) -> [TaskSection] {
        var sections: [TaskSection] = []
        for group in groups {
            if let section = buckets["group:\(group.id)"], !section.tasks.isEmpty {
                sections.append(TaskSection(id: group.id, title: section.title, tasks: section.tasks))
            }
        }
        for (key, section) in buckets where key.hasPrefix("project:") && !section.tasks.isEmpty {
            sections.append(TaskSection(id: key, title: section.title, tasks: section.tasks))
        }
        if let other = buckets["other"], !other.tasks.isEmpty {
            sections.append(other)
        }
        return sections
    }
}
