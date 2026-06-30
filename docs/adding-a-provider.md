# Adding a Provider

This guide walks through adding a new usage vendor to TokenMyBar. Every provider
maps its source data into a `ProviderSnapshot` and is registered with the
`ProviderRegistry`. Use an existing vendor such as Codex as your reference.

All paths below are relative to `packages/menubar`.

## 1. Add a `ProviderID` case

`ProviderID` lives in `Sources/TokenMyBarCore/ProviderSnapshot.swift`. Add your
vendor's case, plus a `displayName` and an `iconName` (an SF Symbol the menu bar
and popover derive from the ID so the icon isn't duplicated per view):

```swift
public enum ProviderID: String, CaseIterable, Codable, Sendable {
    case codex
    case claudeCode = "claude-code"
    case opencode
    case myvendor   // raw value is the on-disk/JSON identifier

    public var displayName: String {
        switch self {
        // ...
        case .myvendor: "My Vendor"
        }
    }

    public var iconName: String {
        switch self {
        // ...
        case .myvendor: "bolt"   // any SF Symbol name
        }
    }
}
```

## 2. Implement `ProviderClient`

The `ProviderClient` protocol is defined in
`Sources/TokenMyBarCore/ProviderClient.swift`:

```swift
public protocol ProviderClient: Sendable {
    var providerID: ProviderID { get }
    func snapshot() async -> ProviderSnapshot
}
```

Create your provider under `Sources/TokenMyBarCore/Vendors/MyVendor/`. Model it
on `Sources/TokenMyBarCore/Vendors/Codex/CodexOAuthUsageProvider.swift`.

### Fetch with `RemoteJSON` helpers

`Sources/TokenMyBarCore/Vendors/Support/RemoteJSON.swift` provides the shared
networking and parsing helpers so you do not hand-roll requests or JSON
spelunking:

- `RemoteJSON.request(url:)` — a pre-configured `URLRequest` (15s timeout,
  `Accept: application/json`). Set auth headers on the returned request.
- `RemoteJSON.fetchObject(_:)` / `fetchText(_:)` — perform the request with a
  bounded retry on transient failures (408/429/5xx and network errors) and throw
  `AuthError.http(status)` for non-2xx responses.
- `RemoteJSON.findObject(in:keys:)` / `findString(in:keys:)` — recursive,
  depth-bounded lookups that tolerate snake_case vs. camelCase key spellings.
- `RemoteJSON.percent(in:remaining:)` — normalizes a percentage into 0...100
  (handles 0...1 fractions); pass `remaining: true` if the vendor reports percent
  *remaining* so the UI sees percent *used*.
- `RemoteJSON.resetDate(in:)` / `resetSubtitle(in:)` — parse reset timestamps or
  seconds-until-reset.
- `RemoteJSON.row(key:title:iconName:object:remaining:)` — builds a `UsageRow`
  with its percent, value string, and reset detail.
- `RemoteJSON.planName(in:keys:)` — extracts a human-friendly plan/tier label.

Read your credentials (e.g. an OAuth token file or cookie) and throw
`AuthError.missingCredentials` when they are absent. `AuthError` is defined in
`Sources/TokenMyBarCore/Vendors/Support/AuthError.swift`.

### Map errors with `ProviderSnapshot.failure(...)`

Do not re-copy the unauthenticated/error/no-data boilerplate. Wrap the fetch in
`do/catch` and route thrown errors through the shared mapper in
`Sources/TokenMyBarCore/Vendors/Support/ProviderSnapshot+Failure.swift`:

```swift
public struct MyVendorUsageProvider: ProviderClient {
    public let providerID: ProviderID = .myvendor

    public init() {}

    public func snapshot() async -> ProviderSnapshot {
        do {
            let token = try Self.credentials()
            var request = RemoteJSON.request(url: "https://api.myvendor.com/usage")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return Self.snapshot(from: try await RemoteJSON.fetchObject(request))
        } catch {
            return .failure(
                error,
                providerID: providerID,
                source: .oauth,
                authSummary: "My Vendor OAuth",
                missingMessage: "My Vendor credentials not found",
                failureMessage: "My Vendor usage failed"
            )
        }
    }

    static func snapshot(from object: [String: Any]) -> ProviderSnapshot {
        let window = RemoteJSON.findObject(in: object, keys: ["primary_window", "primaryWindow"])
        let percent = RemoteJSON.percent(in: window ?? object)
        var rows = [UsageRow]()
        if let window { rows.append(RemoteJSON.row(key: "session", title: "Session", iconName: "timer", object: window)) }

        return ProviderSnapshot(
            providerID: .myvendor,
            status: percent == nil && rows.isEmpty ? .noData : .ok,
            usedTokens: nil,
            usagePercent: percent,
            resetAt: RemoteJSON.resetDate(in: window ?? object),
            primarySource: .oauth,
            sources: [.oauth, .api],
            confidence: .high,
            isEstimated: false,
            authSummary: "My Vendor OAuth",
            usageRows: rows
        )
    }
}
```

`.failure(...)` maps `AuthError.missingCredentials` and HTTP 401/403 to an
`unauthenticated` snapshot, other HTTP statuses to an `error` snapshot (status
code preserved), and anything else to a generic `error`. `unauthenticated`,
`errored`, and `noData` are also available directly if you need them.

Keep the snapshot honest: never invent quota, reset, or cost numbers. Pull the
provider-specific rows into `usageRows` rather than flattening every vendor into
one quota model.

## 3. Register in `ProviderRegistry.defaultProviders()`

Add your provider to `defaultProviders()` in
`Sources/TokenMyBarCore/ProviderClient.swift`. If you also have a local-history
fallback source, wrap the official provider and the fallback in a
`FallbackProvider` (same file) — it returns the official snapshot when its status
is `.ok` and otherwise merges in last-good local data:

```swift
public static func defaultProviders() -> [any ProviderClient] {
    [
        // ...existing providers...
        MyVendorUsageProvider(),
        // or, with a local fallback:
        // FallbackProvider(primary: MyVendorUsageProvider(), fallback: MyVendorLocalUsageProvider()),
    ]
}
```

## 4. Add tests

Unit tests live in `Tests/TokenMyBarCoreTests/` and use `swift-testing`. Follow
`Tests/TokenMyBarCoreTests/OfficialUsageProviderTests.swift`, which exercises
each provider's pure `snapshot(from:)` mapping against a representative JSON
payload — no network required:

```swift
import Testing
@testable import TokenMyBarCore

@Test func myVendorSnapshotReadsPrimaryWindow() {
    let snapshot = MyVendorUsageProvider.snapshot(from: [
        "primary_window": ["usagePercent": 42, "resetInSec": 3600],
    ])

    #expect(snapshot.status == .ok)
    #expect(snapshot.providerID == .myvendor)
    #expect(snapshot.usagePercent == 42)
    #expect(snapshot.usageRows.map(\.key) == ["session"])
}
```

Run the suite with:

```bash
swift test --package-path packages/menubar
```
