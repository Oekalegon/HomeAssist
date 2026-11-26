import XCTest
@testable import HomeAssist

final class AccessTokenTests: XCTestCase {
    func testNormalizedTrimsWhitespaceAndNewlines() {
        XCTAssertEqual(AccessToken.normalized("  abc.def \n"), "abc.def")
    }

    func testLooksCompleteRejectsShortAndSpaced() {
        XCTAssertFalse(AccessToken.looksComplete("x"))
        XCTAssertFalse(AccessToken.looksComplete(String(repeating: "a", count: 60) + " " + String(repeating: "b", count: 60)))
    }

    func testLooksCompleteAcceptsLongToken() {
        XCTAssertTrue(AccessToken.looksComplete(String(repeating: "a", count: 180) + "\n"))
    }
}
