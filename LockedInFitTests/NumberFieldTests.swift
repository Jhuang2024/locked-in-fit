import XCTest
@testable import LockedInFit

/// The typing rules behind every numeric field in the app (see NumberField).
/// The bug these exist for: a field whose text is re-derived from its value on
/// every keystroke can never be empty, so "200" could only ever be deleted
/// down to "2" and never retyped as "100".
@MainActor
final class NumberFieldTests: XCTestCase {

    private var separator: String { NumberText.decimalSeparator }

    // MARK: sanitize

    func testKeepsDigits() {
        XCTAssertEqual(NumberText.sanitize("200"), "200")
        XCTAssertEqual(NumberText.sanitize("1234567"), "1234567")
    }

    func testAllowsHalfTypedInput() {
        // Every intermediate state of retyping 200 as 100 has to survive.
        XCTAssertEqual(NumberText.sanitize("20"), "20")
        XCTAssertEqual(NumberText.sanitize("2"), "2")
        XCTAssertEqual(NumberText.sanitize(""), "")
        XCTAssertEqual(NumberText.sanitize("1"), "1")
        XCTAssertEqual(NumberText.sanitize("10"), "10")
        XCTAssertEqual(NumberText.sanitize("100"), "100")
    }

    func testDropsNonNumericCharacters() {
        XCTAssertEqual(NumberText.sanitize("12abc3"), "123")
        XCTAssertEqual(NumberText.sanitize("1 2 3"), "123")
        XCTAssertEqual(NumberText.sanitize("$45"), "45")
    }

    func testKeepsOnlyTheFirstDecimalSeparator() {
        XCTAssertEqual(NumberText.sanitize("1.5.5"), "1\(separator)55")
        XCTAssertEqual(NumberText.sanitize("1,5"), "1\(separator)5")
        XCTAssertEqual(NumberText.sanitize("."), separator)
    }

    func testStripsLeadingZeros() {
        XCTAssertEqual(NumberText.sanitize("007"), "7")
        XCTAssertEqual(NumberText.sanitize("0"), "0")
        XCTAssertEqual(NumberText.sanitize("0.5"), "0\(separator)5")
    }

    func testMinusOnlyWhenAllowedAndLeading() {
        XCTAssertEqual(NumberText.sanitize("-5"), "5")
        XCTAssertEqual(NumberText.sanitize("-5", allowsNegative: true), "-5")
        XCTAssertEqual(NumberText.sanitize("5-5", allowsNegative: true), "55")
        // A lone minus is a legitimate mid-edit state for "-0.5".
        XCTAssertEqual(NumberText.sanitize("-", allowsNegative: true), "-")
    }

    // MARK: parse

    func testParsesNumbers() {
        XCTAssertEqual(NumberText.parse("200"), 200)
        XCTAssertEqual(NumberText.parse("1.5"), 1.5)
        XCTAssertEqual(NumberText.parse("1,5"), 1.5)
        XCTAssertEqual(NumberText.parse("-0.45"), -0.45)
    }

    func testParsesPartialInput() {
        XCTAssertEqual(NumberText.parse("12."), 12)
        XCTAssertEqual(NumberText.parse(".5"), 0.5)
        XCTAssertEqual(NumberText.parse("-.5"), -0.5)
    }

    func testEmptyMeaningsAreNil() {
        // An empty field is what the value-backed TextField could never
        // produce; NumberField treats nil as 0 until the next keystroke.
        XCTAssertNil(NumberText.parse(""))
        XCTAssertNil(NumberText.parse("-"))
        XCTAssertNil(NumberText.parse("."))
        XCTAssertNil(NumberText.parse("abc"))
        XCTAssertNil(NumberText.parse("1e5"))
    }

    // MARK: display

    func testDisplayRoundsToRequestedPrecision() {
        XCTAssertEqual(NumberText.display(175.4), "175")
        XCTAssertEqual(NumberText.display(175.6), "176")
        XCTAssertEqual(NumberText.display(0.45, fractionDigits: 2), "0\(separator)45")
    }

    func testDisplayTrimsTrailingZerosButKeepsSignificantOnes() {
        XCTAssertEqual(NumberText.display(2200, fractionDigits: 2), "2200")
        XCTAssertEqual(NumberText.display(100.5, fractionDigits: 2), "100\(separator)5")
        XCTAssertEqual(NumberText.display(-0.45, fractionDigits: 2), "-0\(separator)45")
    }

    func testDisplayNeverGroups() {
        // A thousands separator would come straight back in as a decimal
        // separator the next time the field was edited.
        XCTAssertEqual(NumberText.display(12000), "12000")
    }

    func testZeroDisplaysEmptySoThePlaceholderShows() {
        XCTAssertEqual(NumberText.display(0), "")
        XCTAssertEqual(NumberText.display(0.4), "")
    }

    /// The round trip NumberField performs when a field is left alone: text
    /// out of a value, then back to the same value.
    func testDisplayedTextParsesBackToTheDisplayedNumber() {
        for value in [1.0, 7.0, 100.0, 2200.0, 12000.0] {
            XCTAssertEqual(NumberText.parse(NumberText.display(value)), value)
        }
        XCTAssertEqual(NumberText.parse(NumberText.display(72.5, fractionDigits: 1)), 72.5)
    }

    // MARK: integer

    func testIntegerRoundsAndSaturates() {
        XCTAssertEqual(NumberText.integer(8.4), 8)
        XCTAssertEqual(NumberText.integer(8.5), 9)
        // A number pad makes 30 digits easy, and Int(_: Double) traps on those.
        XCTAssertEqual(NumberText.integer(1e30), Int.max)
        XCTAssertEqual(NumberText.integer(-1e30), Int.min)
        XCTAssertEqual(NumberText.integer(.nan), 0)
    }
}
