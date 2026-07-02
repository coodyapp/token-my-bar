import Testing
@testable import TokenMyBarCore

@Test func formatCountRoundsToNearestUnit() {
    #expect(Format.count(999) == "999")
    #expect(Format.count(1_499) == "1K")
    #expect(Format.count(1_500) == "2K")
    #expect(Format.count(1_999_999) == "2M")
}
