import Foundation

// MARK: - Feature

/// Represents a feature request with voting information
public struct Feature: Codable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let description: String
    public let status: FeatureStatus
    public let boardId: String
    public let userId: String?
    public let creatorEmail: String?
    public let createdAt: Date
    public let updatedAt: Date?
    public let upvotes: Int
    public let downvotes: Int
    public let totalVotes: Int

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case status
        case boardId = "board_id"
        case userId = "user_id"
        case creatorEmail = "creator_email"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case upvotes
        case downvotes
        case totalVotes = "total_votes"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        
        let statusString = try container.decode(String.self, forKey: .status)
        status = FeatureStatus(rawValue: statusString) ?? .ideas
        
        boardId = try container.decode(String.self, forKey: .boardId)
        userId = try container.decodeIfPresent(String.self, forKey: .userId)
        creatorEmail = try container.decodeIfPresent(String.self, forKey: .creatorEmail)

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()
        
        let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedAt = updatedAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
        
        upvotes = try container.decode(Int.self, forKey: .upvotes)
        downvotes = try container.decode(Int.self, forKey: .downvotes)
        totalVotes = try container.decode(Int.self, forKey: .totalVotes)
    }
}

// MARK: - FeatureStatus

/// The status of a feature request
public enum FeatureStatus: String, Codable, CaseIterable {
    case ideas = "ideas"
    case inProgress = "in_progress"
    case released = "released"
    
    public var displayName: String {
        switch self {
        case .ideas: return "Ideas"
        case .inProgress: return "In Progress"
        case .released: return "Released"
        }
    }
}

// MARK: - Vote

/// Represents a user's vote on a feature
public struct Vote: Codable, Identifiable, Hashable {
    public let id: String
    public let featureId: String
    public let userId: String
    public let email: String?
    public let voteType: VoteType
    public let createdAt: Date
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case featureId = "feature_id"
        case userId = "user_id"
        case email
        case voteType = "vote_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        featureId = try container.decode(String.self, forKey: .featureId)
        userId = try container.decode(String.self, forKey: .userId)
        email = try container.decodeIfPresent(String.self, forKey: .email)

        let voteTypeString = try container.decode(String.self, forKey: .voteType)
        voteType = VoteType(rawValue: voteTypeString) ?? .up

        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()

        let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedAt = updatedAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    // Manual initializer for fallback cases
    public init(
        id: String,
        featureId: String,
        userId: String,
        email: String? = nil,
        voteType: VoteType,
        createdAt: Date,
        updatedAt: Date?
    ) {
        self.id = id
        self.featureId = featureId
        self.userId = userId
        self.email = email
        self.voteType = voteType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - VoteType

/// The type of vote a user can cast
public enum VoteType: String, Codable, CaseIterable {
    case up = "up"
    
    public var displayName: String {
        switch self {
        case .up: return "Upvote"
        }
    }
    
    public var emoji: String {
        switch self {
        case .up: return "👍"
        }
    }
}

// MARK: - Board

/// Represents a feature board
public struct Board: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let description: String?
    public let userId: String
    public let createdAt: Date
    public let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        userId = try container.decode(String.self, forKey: .userId)
        
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()
        
        let updatedAtString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedAt = updatedAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}
