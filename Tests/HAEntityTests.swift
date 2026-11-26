import XCTest
@testable import HomeAssist

final class HAEntityTests: XCTestCase {
    func testDecodesState() throws {
        let json = #"[{"entity_id":"light.kitchen","state":"on","attributes":{"friendly_name":"Kitchen","brightness":200}}]"#
        let e = try JSONDecoder().decode([HAEntity].self, from: Data(json.utf8))
        XCTAssertEqual(e[0].domain, "light")
        XCTAssertEqual(e[0].friendlyName, "Kitchen")
        XCTAssertTrue(e[0].isOn && e[0].isToggleable)
    }
}
