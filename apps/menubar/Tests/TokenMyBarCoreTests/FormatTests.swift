import Testing
@testable import TokenMyBarCore

@Test func formatCountRoundsToNearestUnit() {
    #expect(Format.count(999) == "999")
    #expect(Format.count(1_499) == "1K")
    #expect(Format.count(1_500) == "2K")
    #expect(Format.count(1_999_999) == "2M")
}

@Test func formatCountRollsOverKToMAtBoundary() {
    // Values in 999_500...999_999 round to 1000 in the K branch and must
    // display "1M", never "1000K".
    #expect(Format.count(999_999) == "1M")
    #expect(Format.count(999_500) == "1M")
    #expect(Format.count(999_499) == "999K")
}
