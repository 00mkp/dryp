import Testing
@testable import DrypCore

@Suite struct DurationParserTests {
    @Test(arguments: [("30", 1800.0), ("1", 60.0), ("+5", 300.0), (" 45 ", 2700.0), ("525600", 31_536_000.0)])
    func wholeMinutes(_ text: String, _ seconds: Double) throws {
        #expect(try DurationParser.parse(text, hours: false) == seconds)
    }

    @Test(arguments: [("2", 7200.0), ("1.5", 5400.0), ("0.25", 900.0), ("8760", 31_536_000.0)])
    func hours(_ text: String, _ seconds: Double) throws {
        #expect(try DurationParser.parse(text, hours: true) == seconds)
    }

    @Test func fractionalHoursRoundToTheNearestMinute() throws {
        #expect(try DurationParser.parse("0.01", hours: true) == 60)   // 36 s → 1 min
    }

    @Test func zeroAndNegativeAreTooShort() {
        #expect(throws: DurationError.tooShort) { try DurationParser.parse("0", hours: false) }
        #expect(throws: DurationError.tooShort) { try DurationParser.parse("-5", hours: false) }
        #expect(throws: DurationError.tooShort) { try DurationParser.parse("0.001", hours: true) }
    }

    @Test func fractionalMinutesAreRejected() {
        #expect(throws: DurationError.notWholeMinutes("1.5")) { try DurationParser.parse("1.5", hours: false) }
    }

    @Test(arguments: ["abc", "", "inf", "nan", "1h", "30m"])
    func nonNumbersAreRejected(_ text: String) {
        #expect(throws: DurationError.notANumber(text)) { try DurationParser.parse(text, hours: false) }
    }

    @Test func infinityInHoursIsRejected() {
        #expect(throws: DurationError.notANumber("inf")) { try DurationParser.parse("inf", hours: true) }
    }

    @Test func overAYearIsTooLong() {
        #expect(throws: DurationError.tooLong) { try DurationParser.parse("99999999", hours: false) }
        #expect(throws: DurationError.tooLong) { try DurationParser.parse("8761", hours: true) }
    }

    @Test func errorsReadAsSentences() {
        #expect(DurationError.notWholeMinutes("1.5").description
            == "minutes must be a whole number ('1.5'); use -h for fractional hours")
        #expect(DurationError.tooShort.description == "duration must be at least 1 minute")
    }
}
