import Foundation

/// Main client for interacting with the Featurefest API
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public class FeaturefestClient {
    
    // MARK: - Properties
    
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    
    // MARK: - Initialization
    
    /// Initialize Featurefest client
    /// - Parameters:
    ///   - baseURL: The base URL for your Featurefest API (default: your Supabase instance)
    ///   - apiKey: Your API key (can be board ID for board-specific access)
    ///   - session: URLSession for network requests
    public init(
        baseURL: String = "https://uisrjfxpjmxmjqgmeldp.supabase.co/rest/v1",
        apiKey: String,
        session: URLSession = .shared
    ) {
        self.baseURL = URL(string: baseURL)!
        self.apiKey = apiKey
        self.session = session
    }
    
    // MARK: - API Methods
    
    /// Fetch all feature requests for the registered board
    /// - Returns: Array of Feature objects
    public func getFeatures() async throws -> [Feature] {
        let endpoint = "/features_with_votes"
        let queryItems = [
            URLQueryItem(name: "board_id", value: "eq.\(apiKey)"),
            URLQueryItem(name: "order", value: "total_votes.desc,created_at.desc")
        ]
        
        let features: [Feature] = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            queryItems: queryItems
        )
        
        return features
    }
    
    /// Create a new feature request
    /// - Parameters:
    ///   - title: The title of the feature request
    ///   - description: The description of the feature request
    ///   - userId: The user ID creating the feature (optional, will use default if nil)
    ///   - creatorEmail: The email of the creator (optional, for notifications)
    ///   - status: The initial status (defaults to .pending)
    /// - Returns: The created Feature object
    public func createFeature(
        title: String,
        description: String,
        userId: String? = nil,
        creatorEmail: String? = nil,
        status: FeatureStatus = .pending
    ) async throws -> Feature {
        let endpoint = "/features"
        let featureData = CreateFeatureRequest(
            title: title,
            description: description,
            status: status.rawValue,
            boardId: apiKey,
            userId: userId,
            creatorEmail: creatorEmail
        )

        let features: [Feature] = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: featureData,
            headers: ["Prefer": "return=representation"]
        )
        
        guard let feature = features.first else {
            throw FeaturefestError.invalidResponse
        }
        
        // Email notifications now handled by Supabase trigger
        
        return feature
    }
    
    /// Vote for a feature (upvote only)
    /// - Parameters:
    ///   - featureId: The ID of the feature to vote for
    ///   - voteType: Only .up is supported
    ///   - userId: The user ID (optional, will use default if nil)
    ///   - email: The voter's email (optional, for notifications)
    /// - Returns: The created vote, or nil if vote was removed
    @discardableResult
    public func vote(
        featureId: String,
        voteType: VoteType,
        userId: String? = nil,
        email: String? = nil
    ) async throws -> Vote? {
        let actualUserId = userId ?? "external-user"
        // Only allow upvotes
        guard voteType == .up else {
            throw FeaturefestError.invalidRequest
        }
        
                // Check if user already voted
        do {
            let existingVote = try await getUserVote(featureId: featureId, userId: actualUserId)
            
            if existingVote != nil {
                // User already voted - remove the vote (toggle off)
                try await removeVote(featureId: featureId, userId: actualUserId)
                return nil
            } else {
                // Create new upvote
                return try await createVote(
                    featureId: featureId,
                    voteType: .up,
                    userId: actualUserId,
                    email: email
                )
            }
        } catch {
            // If checking existing vote fails, try to create new vote anyway
            return try await createVote(
                featureId: featureId,
                voteType: .up,
                userId: actualUserId,
                email: email
            )
        }
    }
    
    /// Convenience method for upvoting
    /// - Parameters:
    ///   - featureId: The ID of the feature to vote for
    ///   - userId: The user ID (optional, will use default if nil)
    ///   - email: The voter's email (optional, for notifications)
    /// - Returns: The created vote, or nil if vote was removed
    @discardableResult
    public func upvote(
        featureId: String,
        userId: String? = nil,
        email: String? = nil
    ) async throws -> Vote? {
        return try await vote(featureId: featureId, voteType: .up, userId: userId, email: email)
    }
    
    /// Remove a user's vote from a feature
    /// - Parameters:
    ///   - featureId: The ID of the feature
    ///   - userId: The user ID
    public func removeVote(featureId: String, userId: String) async throws {
        let endpoint = "/votes"
        let queryItems = [
            URLQueryItem(name: "feature_id", value: "eq.\(featureId)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)")
        ]
        
        let _: EmptyResponse = try await performRequest(
            endpoint: endpoint,
            method: "DELETE",
            queryItems: queryItems
        )
    }
    
    /// Get a user's vote for a specific feature
    /// - Parameters:
    ///   - featureId: The ID of the feature
    ///   - userId: The user ID
    /// - Returns: The user's vote if it exists
    public func getUserVote(featureId: String, userId: String) async throws -> Vote? {
        let endpoint = "/votes"
        let queryItems = [
            URLQueryItem(name: "feature_id", value: "eq.\(featureId)"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]

        let votes: [Vote] = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            queryItems: queryItems
        )

        return votes.first
    }

    /// Fetch votes for multiple features by the same user in a single request
    /// - Parameters:
    ///   - featureIds: The IDs of the features to check
    ///   - userId: The user ID
    /// - Returns: Set of feature IDs the user has voted on
    public func getUserVotes(featureIds: [String], userId: String) async throws -> Set<String> {
        guard !featureIds.isEmpty else { return [] }

        let idsParam = featureIds.joined(separator: ",")
        let endpoint = "/votes"
        let queryItems = [
            URLQueryItem(name: "feature_id", value: "in.(\(idsParam))"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)")
        ]

        let votes: [Vote] = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            queryItems: queryItems
        )

        return Set(votes.map { $0.featureId })
    }
    
    /// Validate that the API key (board ID) exists and is accessible
    /// - Returns: Board information if valid
    public func validateAPIKey() async throws -> Board {
        let endpoint = "/boards"
        let queryItems = [
            URLQueryItem(name: "id", value: "eq.\(apiKey)"),
            URLQueryItem(name: "select", value: "*")
        ]
        
        let boards: [Board] = try await performRequest(
            endpoint: endpoint,
            method: "GET",
            queryItems: queryItems
        )
        
        guard let board = boards.first else {
            throw FeaturefestError.invalidAPIKey
        }
        
        return board
    }
}

// MARK: - Private Methods

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension FeaturefestClient {
    
    private func createVote(
        featureId: String,
        voteType: VoteType,
        userId: String,
        email: String? = nil
    ) async throws -> Vote {
        let endpoint = "/votes"
        let voteData = CreateVoteRequest(
            featureId: featureId,
            userId: userId,
            voteType: voteType.rawValue,
            email: email
        )

        let votes: [Vote] = try await performRequest(
            endpoint: endpoint,
            method: "POST",
            body: voteData,
            headers: ["Prefer": "return=representation"]
        )

        guard let vote = votes.first else {
            throw FeaturefestError.invalidResponse
        }

        return vote
    }

    private func performRequest<T: Codable>(
        endpoint: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        
        var url = baseURL.appendingPathComponent(endpoint)
        
        if let queryItems = queryItems, !queryItems.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = queryItems
            url = components.url!
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Add required headers
        request.addValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpc3JqZnhwam14bWpxZ21lbGRwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk1OTQ3ODIsImV4cCI6MjA3NTE3MDc4Mn0.7J_b2PxzI-x8RCL8FcB7S0pYn9rDFzBtFHXG0JAR5m8", forHTTPHeaderField: "apikey")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add custom headers
        headers?.forEach { key, value in
            request.addValue(value, forHTTPHeaderField: key)
        }
        
        // Add body if provided
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FeaturefestError.invalidResponse
        }

        guard 200...299 ~= httpResponse.statusCode else {
            if let errorData = try? JSONDecoder().decode(SupabaseError.self, from: data) {
                throw FeaturefestError.apiError(errorData.message)
            }
            throw FeaturefestError.httpError(httpResponse.statusCode)
        }
        
        // Handle empty responses for DELETE operations
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Helper Types

private struct CreateVoteRequest: Codable {
    let featureId: String
    let userId: String
    let voteType: String
    let email: String?

    enum CodingKeys: String, CodingKey {
        case featureId = "feature_id"
        case userId = "user_id"
        case voteType = "vote_type"
        case email = "creator_email"
    }
}

private struct CreateFeatureRequest: Codable {
    let title: String
    let description: String
    let status: String
    let boardId: String
    let userId: String?
    let creatorEmail: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case status
        case boardId = "board_id"
        case userId = "user_id"
        case creatorEmail = "creator_email"
    }
}

private struct EmptyResponse: Codable {}

private struct SupabaseError: Codable {
    let message: String
}
