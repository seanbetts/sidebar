import Foundation

struct PendingWriteIndex {
    private let sectionsWithPendingWrites: Set<AppSection>
    private let dirtyFieldsByEntityKey: [EntityKey: Set<String>]

    init(writes: [PendingWriteRecord]) throws {
        var sections = Set<AppSection>()
        var dirtyFields: [EntityKey: Set<String>] = [:]

        for write in writes {
            guard let entityType = WriteEntityType(rawValue: write.entityType),
                  let section = Self.section(for: entityType) else {
                continue
            }
            sections.insert(section)

            guard let entityId = write.entityId else { continue }
            let entityKey = EntityKey(entityType: entityType, entityId: entityId)
            let fields = try Self.fields(for: write, entityType: entityType)
            dirtyFields[entityKey, default: []].formUnion(fields)
        }

        self.sectionsWithPendingWrites = sections
        self.dirtyFieldsByEntityKey = dirtyFields
    }

    func overlaps(section: AppSection) -> Bool {
        sectionsWithPendingWrites.contains(section)
    }

    func dirtyFields(for entityType: WriteEntityType, entityId: String) -> Set<String> {
        dirtyFieldsByEntityKey[EntityKey(entityType: entityType, entityId: entityId)] ?? []
    }

    private static func section(for entityType: WriteEntityType) -> AppSection? {
        switch entityType {
        case .note, .noteFolder:
            return .notes
        case .task:
            return .tasks
        case .message:
            return .chat
        case .website:
            return .websites
        case .file:
            return .files
        case .scratchpad:
            return nil
        }
    }

    private static func fields(
        for write: PendingWriteRecord,
        entityType: WriteEntityType
    ) throws -> Set<String> {
        let operation = WriteOperation(rawValue: write.operationType)
        switch operation {
        case .pin:
            return ["pinned"]
        case .archive:
            return ["archived"]
        case .rename:
            switch entityType {
            case .website:
                return ["title"]
            case .note, .noteFolder:
                return ["name", "path"]
            default:
                return []
            }
        default:
            let object = try JSONSerialization.jsonObject(with: write.payload)
            guard let dictionary = object as? [String: Any] else { return [] }
            return Set(dictionary.keys)
        }
    }
}

private struct EntityKey: Hashable {
    let entityType: WriteEntityType
    let entityId: String
}
