import XCTest
@testable import HomeAssist

final class EntityStatesTests: XCTestCase {
    private func entity(_ id: String, state: String, _ attrs: String = "") throws -> HAEntity {
        let json = #"{"entity_id":"\#(id)","state":"\#(state)","attributes":{"friendly_name":"X"\#(attrs)}}"#
        return try JSONDecoder().decode(HAEntity.self, from: Data(json.utf8))
    }
    private func n(_ d: Double) -> String { EntityFormat.number(d) }

    func testLightSubtitleAndBrightness() throws {
        let on = try entity("light.a", state: "on", #","brightness":128,"rgb_color":[255,0,0]"#)
        XCTAssertEqual(on.brightnessPercent, 50)
        XCTAssertEqual(on.tileSubtitle, "On 50%")
        XCTAssertEqual(on.rgbColor?.red, 1)
        XCTAssertEqual(try entity("light.a", state: "on").tileSubtitle, "On")
        XCTAssertEqual(try entity("light.a", state: "off").tileSubtitle, "Off")
        XCTAssertTrue(on.isActive)
    }

    func testUnavailableIsNotActiveOrToggled() throws {
        let e = try entity("light.a", state: "unavailable")
        XCTAssertTrue(e.isUnavailable)
        XCTAssertFalse(e.isActive)
        XCTAssertEqual(e.tileSubtitle, "Unavailable")
    }

    func testClimateTile() throws {
        let e = try entity("climate.living", state: "heat",
                           #","current_temperature":21.5,"temperature":22,"hvac_action":"heating""#)
        XCTAssertEqual(e.tileValue, n(21.5) + "°")
        XCTAssertEqual(e.tileSubtitle, "Heating → \(n(22))°")
        XCTAssertEqual(e.section, .climate)
        XCTAssertTrue(e.isActive)
        XCTAssertFalse(try entity("climate.living", state: "off").isActive)
    }

    func testSensorTile() throws {
        let e = try entity("sensor.t", state: "19.8", #","unit_of_measurement":"°C","device_class":"temperature""#)
        XCTAssertEqual(e.tileValue, n(19.8) + " °C")
        XCTAssertNil(e.tileSubtitle)
        XCTAssertEqual(e.symbolName, "thermometer.medium")
        XCTAssertEqual(try entity("sensor.t", state: "unavailable").tileValue, "—")
        XCTAssertEqual(try entity("sensor.t", state: "on-ish").tileValue, "on-ish")
    }

    func testSectionsAreOrderedAndEmptyOnesOmitted() throws {
        let list = [try entity("sensor.s", state: "1"), try entity("light.l", state: "on"),
                    try entity("switch.w", state: "on"), try entity("climate.c", state: "off")]
        XCTAssertEqual(list.groupedBySection().map(\.section), [.climate, .lights, .sensors, .other])
        XCTAssertEqual([list[1]].groupedBySection().map(\.section), [.lights])
    }
}

@MainActor
final class FavouritesStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "FavouritesStoreTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }
    private func entity(_ id: String) -> HAEntity {
        try! JSONDecoder().decode(HAEntity.self,
            from: Data(#"{"entity_id":"\#(id)","state":"on","attributes":{}}"#.utf8))
    }

    func testAddRemoveToggleAndNoDuplicates() {
        let store = FavouritesStore(defaults: makeDefaults())
        store.add("light.a"); store.add("light.a"); store.add("light.b")
        XCTAssertEqual(store.ids, ["light.a", "light.b"])
        store.toggle("light.a")
        XCTAssertEqual(store.ids, ["light.b"])
        store.toggle("light.a")
        XCTAssertEqual(store.ids, ["light.b", "light.a"])
    }

    func testPersistsAcrossInstances() {
        let defaults = makeDefaults()
        FavouritesStore(defaults: defaults).add("light.a")
        XCTAssertEqual(FavouritesStore(defaults: defaults).ids, ["light.a"])
    }

    func testMoveWithinSectionLeavesOtherSectionsInPlace() {
        let store = FavouritesStore(defaults: makeDefaults())
        ["light.a", "sensor.x", "light.b", "climate.c", "light.c"].forEach(store.add)
        // Move light.c to the front of the lights section.
        store.move(within: ["light.a", "light.b", "light.c"], from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(store.ids, ["light.c", "sensor.x", "light.a", "climate.c", "light.b"])
    }

    func testEntitiesSkipsMissingButKeepsIDs() {
        let store = FavouritesStore(defaults: makeDefaults())
        store.add("light.gone"); store.add("light.a")
        XCTAssertEqual(store.entities(in: [entity("light.a")]).map(\.entityId), ["light.a"])
        XCTAssertEqual(store.ids, ["light.gone", "light.a"])
    }
}
