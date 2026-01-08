import Foundation

public struct AnyCodable: Codable {
    public let value: Any

    nonisolated public init(_ value: Any) {
        self.value = value
    }

    nonisolated public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            var dict: [String: Any] = [:]
            for (key, anyValue) in dictValue {
                dict[key] = anyValue.value
            }
            value = dict
        } else {
            value = NSNull()
        }
    }

    nonisolated public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map(AnyCodable.init))
        case let dictValue as [String: Any]:
            let encoded = dictValue.mapValues(AnyCodable.init)
            try container.encode(encoded)
        default:
            try container.encodeNil()
        }
    }
}
