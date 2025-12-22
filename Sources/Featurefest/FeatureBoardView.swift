import SwiftUI

/// A simple SwiftUI view for displaying and voting on features from a board
@available(iOS 15.0, macOS 12.0, *)
public struct FeatureBoardView: View {

    // MARK: - Properties

    private let boardId: String
    private let userId: String
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
    public init(boardId: String, userId: String? = nil) {
        self.boardId = boardId
        self.userId = userId ?? UUID().uuidString
        self.client = FeaturefestClient(apiKey: boardId)
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Control
            Picker("Status", selection: $selectedStatus) {
                ForEach(FeatureStatus.allCases, id: \.self) { status in
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
        .navigationTitle("Feature Requests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: toolbarPlacement) {
                Button(action: {
                    showingCreateFeature = true
                }) {
                    Image(systemName: "plus")
                }
            }
        })
        .sheet(isPresented: $showingCreateFeature) {
            CreateFeatureView(client: client, userId: userId) {
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
        List {
            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            ForEach(filteredFeatures) { feature in
                FeatureRow(
                    feature: feature,
                    hasVoted: votedFeatures.contains(feature.id),
                    onUpvote: { await upvote(feature) }
                )
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
    }

    // MARK: - Actions

    private func loadFeatures() async {
        isLoading = true
        errorMessage = nil

        do {
            features = try await client.getFeatures()
            await checkUserVotes()
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func checkUserVotes() async {
        var voted = Set<String>()

        for feature in features {
            do {
                let vote = try await client.getUserVote(featureId: feature.id, userId: userId)
                if vote != nil {
                    voted.insert(feature.id)
                }
            } catch {
                // Ignore errors when checking votes
                continue
            }
        }

        votedFeatures = voted
    }

    private func upvote(_ feature: Feature) async {
        do {
            let result = try await client.upvote(featureId: feature.id, userId: userId)

            // Toggle voted state based on result
            if result != nil {
                votedFeatures.insert(feature.id)
            } else {
                votedFeatures.remove(feature.id)
            }

            await loadFeatures()
        } catch {
            errorMessage = "Failed to vote: \(error.localizedDescription)"
        }
    }
}

// MARK: - Feature Row Component

@available(iOS 15.0, macOS 12.0, *)
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
                    .lineLimit(3)

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
                VStack(spacing: 4) {
                    Image(systemName: hasVoted ? "chevron.up.circle.fill" : "chevron.up.circle")
                        .font(.system(size: 32))
                    Text("\(feature.totalVotes)")
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                }
                .foregroundColor(hasVoted ? .blue : .secondary)
            }
            .buttonStyle(.borderless)
            .disabled(isVoting)
        }
        .padding(.vertical, 4)
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

@available(iOS 15.0, macOS 12.0, *)
private struct CreateFeatureView: View {
    let client: FeaturefestClient
    let userId: String
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

                        Button("Create") {
                            Task {
                                await createFeature()
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
                userId: userId
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

@available(iOS 15.0, macOS 12.0, *)
struct FeatureBoardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FeatureBoardView(boardId: "a4f09436-a98e-4a04-a3bc-8ea1b467fdc1")
                .navigationTitle("Feature Requests")
        }
    }
}
