import XCTest
@testable import music

final class OutputFormatTests: XCTestCase {
    // A serialization failure must surface as an error object, not a silent "{}"
    // that a machine consumer would read as "empty but fine".
    func testJSONSerializationFailureReturnsErrorObject() {
        let fmt = OutputFormat(mode: .json)
        let out = fmt.render(["when": Date()])  // Date is not JSONSerialization-valid
        XCTAssertNotEqual(out, "{}", "serialization failure should not be silent")
        XCTAssertTrue(out.contains("error"), "expected an error object, got: \(out)")
    }

    func testValidJSONStillRenders() {
        let fmt = OutputFormat(mode: .json)
        let out = fmt.render(["title": "Alpha"])
        XCTAssertTrue(out.contains("\"title\""))
        XCTAssertTrue(out.contains("Alpha"))
    }
}
