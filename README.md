# Featurefest Swift Package

A Swift package for integrating feature voting into iOS apps.

## Install package

In xcode go to File -> "Add package dependencies..." and search for https://github.com/AlexanderKvamme/featurefest-swift

## Demo
1. Navigate to `Demo/ContentView.swift` in the file browser
2. Click the **Resume** button (▶️) in the preview pane on the right
3. See it running with live data!

## Quick Start

The easiest way to add feature voting to your app is with `FeatureBoardView`:

```swift
import SwiftUI
import Featurefest

struct MyApp: View {
    var body: some View {
        NavigationView {
            FeatureBoardView(boardId: "your-board-id-here")
                .navigationTitle("Feature Requests")
        }
    }
}
```

That's it! The view includes:
- Automatic feature loading
- Pull-to-refresh
- Upvoting with visual feedback
- Status badges (Ideas, In Progress, Released)
- Empty state UI
- Error handling

## Advanced Usage

Featurefest is 100% customizable. Just use the API instead of the FeatureBoardView, and build your own interface and make them interact with the API method described below.

### Using the Client Directly

```swift
import Featurefest

// Initialize client
let client = FeaturefestClient(apiKey: "your-board-id-here")

// Get features
let features = try await client.getFeatures()

// Upvote a feature
try await client.upvote(featureId: "feature-id", userId: "user-123")

// Create a feature request
let feature = try await client.createFeature(
    title: "New Feature",
    description: "Feature description",
    userId: "user-123"
)
```

### User IDs

By default, `FeatureBoardView` automatically uses the device's `identifierForVendor` as the user ID. This provides a consistent UUID that persists across app launches while remaining unique per device.

If you need to use a custom user ID (for authenticated users, for example), you can pass one - but it **must be in UUID format**:

```swift
FeatureBoardView(
    boardId: "your-board-id",
    userId: "550e8400-e29b-41d4-a947-926655440000"  // Must be valid UUID format
)
```

### Email Tracking

You can optionally pass a user's email to associate votes with email addresses. This allows you to send emails to users from the web dashboard later:

```swift
FeatureBoardView(
    boardId: "your-board-id",
    userEmail: "user@example.com"
)
```

## Building a Full App

To create a complete iOS app:

1. Create a new iOS app in Xcode
2. Add this package: File > Add Packages > Add Local... (select this folder)
3. Import and use:
   ```swift
   import Featurefest

   FeatureBoardView(boardId: "your-board-id")
   ```

## Email Notifications

Email notifications are automatically handled by Supabase database triggers when features are created. No additional client-side setup required.

## More Examples

```swift


struct FeaturefestScreen: View {
    var body: some View {
        Text("Hello")
            .onAppear {
                Task {
                    do {
                        let board = try await client.validateAPIKey()
                        print("Connected to board: \(board.name)")
                    } catch {
                        print("Invalid API key: \(error.localizedDescription)")
                    }
                    
                    do {
                        let features = try await client.getFeatures()
                        for feature in features {
                            print("\(feature.title) - \(feature.upvotes) upvotes")
                        }
                    } catch {
                        print("Failed to fetch features: \(error.localizedDescription)")
                    }
                }
            }
    }
}

struct FeaturefestCard: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text(description)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white.opacity(0.08))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    FeaturefestScreen()
}
