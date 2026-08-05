import Foundation

public enum NapaxiWorkspacePolicy: String, Codable, Equatable, Sendable {
    case useProjectDefault = "use_project_default"
    case keepCurrent = "keep_current"
    case usePersonalDefault = "use_personal_default"

    public var wireValue: String { rawValue }
}

public struct NapaxiProject: Codable, Equatable, Sendable {
    public var id: String
    public var accountId: String
    public var agentId: String
    public var name: String
    public var defaultWorkspaceId: String
    public var state: String
    public var createdAt: String
    public var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, state
        case accountId = "account_id"
        case agentId = "agent_id"
        case defaultWorkspaceId = "default_workspace_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

public struct NapaxiSessionPlacement: Codable, Equatable, Sendable {
    public var threadId: String
    public var projectId: String?
    public var runtimeWorkspaceId: String
    public var workingDirectory: String?
    public var revision: Int64
    public var projectEnteredAt: String?
    public var workspaceUpdatedAt: String

    enum CodingKeys: String, CodingKey {
        case revision
        case threadId = "thread_id"
        case projectId = "project_id"
        case runtimeWorkspaceId = "runtime_workspace_id"
        case workingDirectory = "working_directory"
        case projectEnteredAt = "project_entered_at"
        case workspaceUpdatedAt = "workspace_updated_at"
    }

    public func runtimeMatchesProject(_ project: NapaxiProject) -> Bool {
        runtimeWorkspaceId == project.defaultWorkspaceId
    }
}
