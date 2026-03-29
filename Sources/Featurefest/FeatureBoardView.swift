import SwiftUI

// MARK: - FeatureBoardStyle

/// Controls the appearance of FeatureBoardView
public struct FeatureBoardStyle {
    public var accentColor: Color
    public var colorScheme: ColorScheme?

    public init(accentColor: Color = .blue, colorScheme: ColorScheme? = nil) {
        self.accentColor = accentColor
        self.colorScheme = colorScheme
    }

    public static let `default` = FeatureBoardStyle()
    public static let dark = FeatureBoardStyle(colorScheme: .dark)
}

/// A simple SwiftUI view for displaying and voting on features from a board
@available(iOS 15.0, *)
public struct FeatureBoardView: View {

    // MARK: - Properties

    private let boardId: String
    private let userId: String
    private let userEmail: String?
    private let style: FeatureBoardStyle
    private let client: FeaturefestClient

    @State private var features: [Feature] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var votedFeatures: Set<String> = []
    @State private var selectedStatus: FeatureStatus = .pending
    @State private var showingCreateFeature = false

    // MARK: - Initialization

    /// Create a feature board view
    /// - Parameters:
    ///   - boardId: The UUID of the board to display
    ///   - userId: Optional user ID for vote tracking (defaults to device-specific ID)
    ///   - userEmail: Optional email for notifications
    ///   - style: Visual style configuration (accent color, color scheme)
    public init(boardId: String,
                userId: String? = nil,
                userEmail: String? = nil,
                style: FeatureBoardStyle = .default) {
        self.boardId = boardId
        self.userId = userId ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.userEmail = userEmail
        self.style = style
        self.client = FeaturefestClient(apiKey: boardId)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Control
            Picker("Status", selection: $selectedStatus) {
                ForEach(FeatureStatus.allCases.filter { $0 != .completed && $0 != .rejected }, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .padding(.bottom, 8)

            // Content
            if isLoading && features.isEmpty {
                Spacer()
                ProgressView("Loading features...")
                Spacer()
            } else if filteredFeatures.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                featureList
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Feature Requests")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(style.colorScheme)
        .toolbar(content: {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: {
                    showingCreateFeature = true
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accentColor)
                }
            }
        })
        .sheet(isPresented: $showingCreateFeature) {
            CreateFeatureView(client: client, userId: userId, userEmail: userEmail) {
                await loadFeatures()
            }
        }
        .task {
            await loadFeatures()
        }
        .refreshable {
            await loadFeatures()
        }
    }

    // MARK: - Computed Properties

    private var filteredFeatures: [Feature] {
        features.filter { $0.status == selectedStatus }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .navigationBarTrailing
        #else
        return .automatic
        #endif
    }

    // MARK: - View Components

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No \(selectedStatus.displayName.lowercased())")
                .font(.title2)
                .foregroundColor(.secondary)

            Text(emptyStateMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }

    private var statusIcon: String {
        switch selectedStatus {
        case .pending:
            return "clock.fill"
        case .inReview:
            return "eye.fill"
        case .planned:
            return "calendar.badge.checkmark"
        case .inProgress:
            return "hammer.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .rejected:
            return "xmark.circle.fill"
        }
    }

    private var emptyStateMessage: String {
        switch selectedStatus {
        case .pending:
            return "Be the first to request a feature!"
        case .inReview:
            return "No features are currently under review"
        case .planned:
            return "No features are planned yet"
        case .inProgress:
            return "No features are currently in progress"
        case .completed:
            return "No features have been completed yet"
        case .rejected:
            return "No features have been rejected"
        }
    }

    private var featureList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                }

                ForEach(filteredFeatures) { feature in
                    NavigationLink(destination: FeatureDetailView(
                        feature: feature,
                        hasVoted: votedFeatures.contains(feature.id),
                        accentColor: style.accentColor,
                        client: client,
                        userId: userId,
                        onUpvote: { await upvote(feature) }
                    )) {
                        FeatureRow(
                            feature: feature,
                            hasVoted: votedFeatures.contains(feature.id),
                            accentColor: style.accentColor,
                            onUpvote: { await upvote(feature) }
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    // MARK: - Actions

    private func loadFeatures() async {
        isLoading = true
        errorMessage = nil

        do {
            features = try await client.getFeatures()
            await checkUserVotes()
        } catch {
            // Ignore cancellation errors (happen during view dismissal/recreation)
            if (error as NSError).code != NSURLErrorCancelled {
                errorMessage = "Failed to load: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    private func checkUserVotes() async {
        do {
            votedFeatures = try await client.getUserVotes(featureIds: features.map { $0.id }, userId: userId)
        } catch {
            // Ignore errors when checking votes
        }
    }

    private func upvote(_ feature: Feature) async {
        // Optimistically toggle the vote state immediately (for instant button color change)
        let wasVoted = votedFeatures.contains(feature.id)
        if wasVoted {
            votedFeatures.remove(feature.id)
        } else {
            votedFeatures.insert(feature.id)
        }

        // Make the network call in the background
        do {
            let result = try await client.upvote(featureId: feature.id, userId: userId, email: userEmail)

            // Verify the result matches our optimistic update
            let actuallyVoted = result != nil
            if actuallyVoted != !wasVoted {
                // Server state doesn't match optimistic state, revert
                if actuallyVoted {
                    votedFeatures.insert(feature.id)
                } else {
                    votedFeatures.remove(feature.id)
                }
            }

            // Reload features to get accurate counts from server
            await loadFeatures()
        } catch {
            // Revert optimistic update on error
            if wasVoted {
                votedFeatures.insert(feature.id)
            } else {
                votedFeatures.remove(feature.id)
            }

            errorMessage = "Failed to vote: \(error.localizedDescription)"
        }
    }
}

// MARK: - Feature Row Component

@available(iOS 15.0, *)
private struct FeatureRow: View {
    let feature: Feature
    let hasVoted: Bool
    let accentColor: Color
    let onUpvote: () async -> Void

    @State private var isVoting = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Content
            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(feature.title)
                    .font(.headline)

                // Description
                Text(feature.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(5)

                // Status badge
                Text(feature.status.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .cornerRadius(6)
            }

            Spacer()

            // Large Upvote button on the right
            Button {
                Task {
                    isVoting = true
                    await onUpvote()
                    isVoting = false
                }
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(hasVoted ? accentColor : .primary)
                    Text("\(feature.totalVotes)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(hasVoted ? accentColor : .primary)
                }
                .frame(width: 56, height: 70)
                .background(hasVoted ? accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .buttonStyle(.borderless)
            .disabled(isVoting)
        }
        .padding()
    }

    private var statusColor: Color {
        switch feature.status {
        case .pending:
            return .gray
        case .inReview:
            return .blue
        case .planned:
            return .purple
        case .inProgress:
            return .orange
        case .completed:
            return .green
        case .rejected:
            return .red
        }
    }
}

// MARK: - Feature Detail View

@available(iOS 15.0, *)
private struct FeatureDetailView: View {
    let feature: Feature
    let hasVoted: Bool
    let accentColor: Color
    let client: FeaturefestClient
    let userId: String
    let onUpvote: () async -> Void

    @State private var isVoting = false
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false
    @State private var commentText = ""
    @State private var commentName = ""
    @State private var isPostingComment = false
    @State private var commentError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text(feature.title)
                    .font(.title)
                    .fontWeight(.bold)

                // Status badge
                HStack {
                    Text(feature.status.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(statusColor.opacity(0.15))
                        .foregroundColor(statusColor)
                        .cornerRadius(8)
                    Spacer()
                }

                // Description
                Text(feature.description)
                    .font(.body)
                    .foregroundColor(.primary)

                // Upvote button
                Button {
                    Task {
                        isVoting = true
                        await onUpvote()
                        isVoting = false
                    }
                } label: {
                    HStack {
                        Image(systemName: hasVoted ? "chevron.up.circle.fill" : "chevron.up.circle")
                            .font(.system(size: 24))
                        Text("\(feature.totalVotes) votes")
                            .font(.headline)
                        Spacer()
                        if isVoting { ProgressView() }
                    }
                    .padding()
                    .background(hasVoted ? accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                    .foregroundColor(hasVoted ? accentColor : .primary)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isVoting)

                // MARK: Comments
                Divider()

                Text("Comments")
                    .font(.headline)

                if isLoadingComments {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if comments.isEmpty {
                    Text("No comments yet. Be the first!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.displayName)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(comment.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(comment.message)
                                .font(.subheadline)
                        }
                        .padding(12)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(10)
                    }
                }

                // MARK: Add comment
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Your name (optional)", text: $commentName)
                        .font(.subheadline)
                        .padding(10)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(8)

                    ZStack(alignment: .topLeading) {
                        if commentText.isEmpty {
                            Text("Leave a comment…")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                        }
                        TextEditor(text: $commentText)
                            .font(.subheadline)
                            .frame(minHeight: 80)
                            .padding(6)
                            .opacity(commentText.isEmpty ? 0.85 : 1)
                    }
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)

                    if let commentError {
                        Text(commentError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button {
                        Task { await postComment() }
                    } label: {
                        HStack {
                            if isPostingComment { ProgressView() }
                            Text("Post Comment")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(commentText.trimmingCharacters(in: .whitespaces).isEmpty || isPostingComment)
                }
            }
            .padding()
        }
        .navigationTitle("Feature Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadComments() }
    }

    private func loadComments() async {
        isLoadingComments = true
        comments = (try? await client.getComments(featureId: feature.id)) ?? []
        isLoadingComments = false
    }

    private func postComment() async {
        let trimmed = commentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isPostingComment = true
        commentError = nil
        do {
            let name = commentName.trimmingCharacters(in: .whitespaces)
            try await client.postComment(
                featureId: feature.id,
                message: trimmed,
                name: name.isEmpty ? nil : name,
                deviceId: userId
            )
            commentText = ""
            commentName = ""
            await loadComments()
        } catch {
            commentError = "Failed to post: \(error.localizedDescription)"
        }
        isPostingComment = false
    }

    private var statusColor: Color {
        switch feature.status {
        case .pending: return .gray
        case .inReview: return .blue
        case .planned: return .purple
        case .inProgress: return .orange
        case .completed: return .green
        case .rejected: return .red
        }
    }
}

// MARK: - Create Feature View

@available(iOS 15.0, *)
private struct CreateFeatureView: View {
    let client: FeaturefestClient
    let userId: String
    let userEmail: String?
    let onFeatureCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                }

                Section(header: Text("Description")) {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section {
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }

                        Spacer()

                        Button {
                            Task {
                                await createFeature()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                                Text("Create")
                            }
                        }
                        .disabled(title.isEmpty || description.isEmpty || isCreating)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("New Feature Request")
        }
    }

    private func createFeature() async {
        isCreating = true
        errorMessage = nil

        do {
            _ = try await client.createFeature(
                title: title,
                description: description,
                userId: userId,
                creatorEmail: userEmail
            )

            await onFeatureCreated()
            dismiss()
        } catch {
            errorMessage = "Failed to create: \(error.localizedDescription)"
        }

        isCreating = false
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct FeatureBoardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FeatureBoardView(boardId: "a4f09436-a98e-4a04-a3bc-8ea1b467fdc1")
                .navigationTitle("Feature Requests")
        }
    }
}
