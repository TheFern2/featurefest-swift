import SwiftUI

/// A simple SwiftUI view for displaying and voting on features from a board
@available(iOS 15.0, *)
public struct FeatureBoardView: View {

    // MARK: - Properties

    private let boardId: String
    private let userId: String
    private let userEmail: String?
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
    public init(boardId: String,
                userId: String? = nil,
                userEmail: String? = nil) {
        self.boardId = boardId
        self.userId = userId ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.userEmail = userEmail
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
        .background(Color(red: 0xf7/255, green: 0xf7/255, blue: 0xf9/255))
        .navigationTitle("Feature Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: {
                    showingCreateFeature = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
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
                        onUpvote: { await upvote(feature) }
                    )) {
                        FeatureRow(
                            feature: feature,
                            hasVoted: votedFeatures.contains(feature.id),
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
                        .foregroundColor(hasVoted ? .blue : .black)
                    Text("\(feature.totalVotes)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(hasVoted ? .blue : .black)
                }
                .frame(width: 56, height: 70)
                .background(hasVoted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
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
    let onUpvote: () async -> Void

    @State private var isVoting = false

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
                        if isVoting {
                            ProgressView()
                        }
                    }
                    .padding()
                    .background(hasVoted ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .foregroundColor(hasVoted ? .blue : .primary)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isVoting)

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Feature Details")
        .navigationBarTitleDisplayMode(.inline)
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
