import Foundation
import Testing
@testable import TokenMyBarCore

@Test func vendorUsageReportUsesUniformJSONShape() throws {
    let snapshot = ProviderSnapshot(
        providerID: .codex,
        status: .ok,
        usedTokens: nil,
        usagePercent: 67.4,
        refreshedAt: Date(timeIntervalSince1970: 1_700_000_000),
        primarySource: .oauth,
        confidence: .high,
        isEstimated: false,
        planName: "Plus",
        usageRows: [
            UsageRow(
                key: "session",
                title: "Session",
                subtitle: "Included",
                value: "67%",
                detail: "Resets in 1h",
                percent: 67.4,
                unit: .requests
            ),
        ]
    )

    let data = try JSONEncoder.tokenMyBar.encode(snapshot.vendorReport())
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    #expect(object?["vendor"] as? String == "codex")
    #expect(object?["name"] as? String == "OpenAI Codex")
    #expect(object?["plan"] as? String == "Plus")
    #expect(object?["status"] as? String == "ok")
    #expect(object?["text"] as? String == "OpenAI Codex 67%")
    #expect(object?["percentage"] as? Int == 67)
    #expect(object?["class"] as? String == "normal")
    #expect(object?["updated_at"] as? String == "2023-11-14T22:13:20Z")

    let windows = object?["windows"] as? [[String: Any]]
    #expect(windows?.first?["key"] as? String == "session")
    #expect(windows?.first?["title"] as? String == "Session")
    #expect(windows?.first?["percent"] as? Double == 67.4)
    #expect(windows?.first?["value"] as? String == "67%")
    #expect(windows?.first?["detail"] as? String == "Resets in 1h")
}

@Test func vendorUsageReportClassTracksSeverityAndStatus() {
    let warning = ProviderSnapshot(
        providerID: .opencode,
        status: .ok,
        usedTokens: nil,
        usagePercent: 80,
        primarySource: .browserCookie,
        confidence: .high,
        isEstimated: false
    ).vendorReport()

    let unauthenticated = ProviderSnapshot(
        providerID: .claudeCode,
        status: .unauthenticated,
        usedTokens: nil,
        primarySource: .oauth,
        confidence: .high,
        isEstimated: false
    ).vendorReport()

    #expect(warning.cssClass == "warning")
    #expect(unauthenticated.cssClass == "unauthenticated")
}
