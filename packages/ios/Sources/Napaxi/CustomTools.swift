import Foundation

public struct NapaxiCustomToolDefinition: Codable, Equatable, Sendable {
    public static let defaultParameters: [String: NapaxiJSONValue] = [
        "type": .string("object"),
        "properties": .object([:]),
    ]

    public var name: String
    public var description: String
    public var parameters: [String: NapaxiJSONValue]
    public var effect: String

    public init(
        name: String,
        description: String,
        parameters: [String: NapaxiJSONValue] = Self.defaultParameters,
        effect: String = "unknown"
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.effect = effect
    }

    public init(raw: [String: NapaxiJSONValue]) {
        self = Self.fromJson(raw)
    }

    public init(json: [String: NapaxiJSONValue]) {
        self = Self.fromJson(json)
    }

    public static func fromJson(_ json: [String: NapaxiJSONValue]) -> Self {
        let parameters: [String: NapaxiJSONValue]
        if case .object(let object)? = json["parameters"] {
            parameters = object
        } else {
            parameters = Self.defaultParameters
        }
        return Self(
            name: json["name"]?.stringValue ?? "",
            description: json["description"]?.stringValue ?? "",
            parameters: parameters,
            effect: json["effect"]?.stringValue ?? "unknown"
        )
    }

    public func toJson() -> [String: NapaxiJSONValue] {
        [
            "name": .string(name),
            "description": .string(description),
            "parameters": .object(parameters),
            "effect": .string(effect),
        ]
    }

    public func toJsonString() throws -> String {
        try jsonString()
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case parameters
        case effect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        self.parameters = (try? container.decode([String: NapaxiJSONValue].self, forKey: .parameters))
            ?? Self.defaultParameters
        self.effect = try container.decodeIfPresent(String.self, forKey: .effect) ?? "unknown"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(effect, forKey: .effect)
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toJson())
    }

    public func jsonString() throws -> String {
        try NapaxiRawJSON(jsonValue()).jsonString()
    }

    public static func jsonString(for tools: [NapaxiCustomToolDefinition]) throws -> String {
        try NapaxiRawJSON(.array(tools.map { .object($0.toJson()) })).jsonString()
    }
}
