import Foundation
import sideBarShared

struct ChartPointPayload: Decodable {
    let id: String?
    let label: String?
    let xLabel: String?
    let value: Double?
    let yValue: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case label
        case xLabel = "x"
        case value
        case yValue = "y"
    }

    var resolvedPoint: AgentWorkspaceChartPoint? {
        guard let resolvedLabel = label?.trimmedOrNil ?? xLabel?.trimmedOrNil,
              let resolvedValue = value ?? yValue else {
            return nil
        }
        return AgentWorkspaceChartPoint(id: id, label: resolvedLabel, value: resolvedValue)
    }
}

struct FormFieldPayload: Decodable {
    let id: String?
    let key: String?
    let label: String?
    let value: String?
    let placeholder: String?
    let defaultValue: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WorkspacePayloadCodingKey.self)
        id = container.decodeTrimmedString(forKeys: ["id"])
        key = container.decodeTrimmedString(forKeys: ["key", "name"])
        label = container.decodeTrimmedString(forKeys: ["label"])
        value = container.decodeString(forKeys: ["value"])
        placeholder = container.decodeTrimmedString(forKeys: ["placeholder"])
        defaultValue = container.decodeString(forKeys: ["default_value", "defaultValue"])
    }

    var resolvedField: AgentWorkspaceFormField? {
        let resolvedId = id?.trimmedOrNil ?? key?.trimmedOrNil ?? label?.trimmedOrNil?.lowercased()
        let resolvedLabel = label?.trimmedOrNil
            ?? key?.trimmedOrNil?.replacingOccurrences(of: "_", with: " ").capitalized
        guard let resolvedId, let resolvedLabel else {
            return nil
        }

        return AgentWorkspaceFormField(
            id: resolvedId,
            label: resolvedLabel,
            value: value ?? defaultValue ?? "",
            placeholder: placeholder?.trimmedOrNil
        )
    }
}

struct ActionItemPayload: Decodable {
    let id: String?
    let title: String?
    let label: String?
    let systemImage: String?
    let style: String?
    let variant: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WorkspacePayloadCodingKey.self)
        id = container.decodeTrimmedString(forKeys: ["id"])
        title = container.decodeTrimmedString(forKeys: ["title"])
        label = container.decodeTrimmedString(forKeys: ["label"])
        systemImage = container.decodeTrimmedString(forKeys: ["system_image", "systemImage"])
        style = container.decodeTrimmedString(forKeys: ["style"])
        variant = container.decodeTrimmedString(forKeys: ["variant"])
    }

    var resolvedItem: AgentWorkspaceActionItem? {
        guard let resolvedTitle = title?.trimmedOrNil ?? label?.trimmedOrNil else {
            return nil
        }

        let normalizedStyle = (style?.trimmedOrNil ?? variant?.trimmedOrNil ?? "").lowercased()
        let resolvedStyle: AgentWorkspaceActionItem.Style =
            normalizedStyle == "primary" || normalizedStyle == "prominent"
            ? .primary
            : .secondary

        return AgentWorkspaceActionItem(
            id: id?.trimmedOrNil ?? resolvedTitle.lowercased().replacingOccurrences(of: " ", with: "_"),
            title: resolvedTitle,
            systemImage: systemImage?.trimmedOrNil,
            style: resolvedStyle
        )
    }
}

struct WorkspacePayloadCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Dictionary where Key == String, Value == String {
    nonisolated func firstTrimmedString(forKeys keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.trimmedOrNil {
                return value
            }
        }
        return nil
    }

    nonisolated func decodeJSON<T: Decodable>(_ type: T.Type, forKeys keys: [String]) -> T? {
        guard let raw = firstTrimmedString(forKeys: keys),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    nonisolated func stringArray(forKeys keys: [String]) -> [String] {
        guard let raw = firstTrimmedString(forKeys: keys) else {
            return []
        }
        if let decoded = decodeJSON([String].self, forKeys: keys) {
            return decoded.compactMap(\.trimmedOrNil)
        }
        if let values = rawJSONArray(from: raw) {
            return values.compactMap(Self.stringValue(from:))
        }
        return raw
            .split(separator: ",")
            .compactMap { String($0).trimmingCharacters(in: .whitespacesAndNewlines).trimmedOrNil }
    }

    nonisolated func doubleArray(forKeys keys: [String]) -> [Double] {
        guard let raw = firstTrimmedString(forKeys: keys) else {
            return []
        }
        if let values = rawJSONArray(from: raw) {
            return values.compactMap(Self.doubleValue(from:))
        }
        return raw
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    nonisolated func doubleValue(forKeys keys: [String]) -> Double? {
        firstTrimmedString(forKeys: keys).flatMap(Double.init)
    }

    nonisolated private func rawJSONArray(from raw: String) -> [Any]? {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              let array = value as? [Any] else {
            return nil
        }
        return array
    }

    nonisolated private static func stringValue(from value: Any) -> String? {
        if let string = value as? String {
            return string.trimmedOrNil
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    nonisolated private static func doubleValue(from value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

extension KeyedDecodingContainer where K == WorkspacePayloadCodingKey {
    func decodeString(forKeys keys: [String]) -> String? {
        for key in keys {
            guard let codingKey = WorkspacePayloadCodingKey(stringValue: key) else {
                continue
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeTrimmedString(forKeys keys: [String]) -> String? {
        decodeString(forKeys: keys)?.trimmedOrNil
    }
}
