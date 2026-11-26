import XCTest
@testable import HomeAssist

final class RoomsTests: XCTestCase {
    private func entity(_ id: String, state: String = "off", _ attrs: String = "") -> HAEntity {
        try! JSONDecoder().decode(HAEntity.self, from: Data(
            #"{"entity_id":"\#(id)","state":"\#(state)","attributes":{"friendly_name":"\#(id)"\#(attrs)}}"#.utf8))
    }
    private let kitchen = HAArea(areaId: "k", name: "Kitchen")
    private let living = HAArea(areaId: "l", name: "Living room")

    func testDecodesRegistryReplies() throws {
        let areas = try HARegistryClient.result([HAArea].self, from: Data(
            #"{"id":1,"type":"result","success":true,"result":[{"area_id":"k","name":"Kitchen","icon":null,"floor_id":null}]}"#.utf8))
        XCTAssertEqual(areas, [kitchen])
        let entries = try HARegistryClient.result([HAEntityRegistryEntry].self, from: Data(
            #"{"id":3,"type":"result","success":true,"result":[{"entity_id":"light.a","area_id":null,"device_id":"d1","hidden_by":null,"disabled_by":"user"}]}"#.utf8))
        XCTAssertEqual(entries.first?.deviceId, "d1")
        XCTAssertEqual(entries.first?.disabledBy, "user")
    }

    func testNonAdminReplyBecomesRegistryDenied() {
        let json = #"{"id":1,"type":"result","success":false,"error":{"code":"unauthorized","message":"Unauthorized"}}"#
        XCTAssertThrowsError(try HARegistryClient.result([HAArea].self, from: Data(json.utf8))) {
            XCTAssertEqual(($0 as? HAError)?.errorDescription, HAError.registryDenied.errorDescription)
        }
    }

    func testEntityAreaOverridesDeviceAreaAndDeviceAreaIsInherited() {
        let registry = HARegistry.build(
            areas: [kitchen, living],
            devices: [HADevice(id: "d1", areaId: "k"), HADevice(id: "d2", areaId: nil)],
            entities: [
                HAEntityRegistryEntry(entityId: "light.inherits", areaId: nil, deviceId: "d1", hiddenBy: nil, disabledBy: nil),
                HAEntityRegistryEntry(entityId: "light.overrides", areaId: "l", deviceId: "d1", hiddenBy: nil, disabledBy: nil),
                HAEntityRegistryEntry(entityId: "light.none", areaId: nil, deviceId: "d2", hiddenBy: nil, disabledBy: nil),
            ])
        XCTAssertEqual(registry.entityAreas, ["light.inherits": "k", "light.overrides": "l"])
    }

    func testRoomsSortHideAndUnassignedLast() {
        let registry = HARegistry(areas: [living, kitchen, HAArea(areaId: "e", name: "Empty")],
                                  entityAreas: ["light.k": "k", "light.l": "l", "light.hidden": "k", "light.stale": "gone"],
                                  hiddenEntityIDs: ["light.hidden"])
        let rooms = registry.rooms(for: [entity("light.l"), entity("light.k"), entity("light.hidden"),
                                         entity("light.stale"), entity("sensor.loose")])
        XCTAssertEqual(rooms.map(\.name), ["Kitchen", "Living room", "Unassigned"], "empty rooms omitted")
        XCTAssertEqual(rooms[0].entities.map(\.entityId), ["light.k"], "hidden entity excluded")
        XCTAssertEqual(rooms[2].entities.map(\.entityId).sorted(), ["light.stale", "sensor.loose"],
                       "an entity in an unknown area is unassigned")
    }

    func testNoUnassignedRoomWhenEverythingHasOne() {
        let registry = HARegistry(areas: [kitchen], entityAreas: ["light.k": "k"], hiddenEntityIDs: [])
        XCTAssertEqual(registry.rooms(for: [entity("light.k")]).map(\.id), ["k"])
    }

    func testSummary() {
        let room = Room(id: "k", name: "Kitchen", entities: [
            entity("light.a", state: "on"), entity("light.b", state: "on"), entity("light.c", state: "off"),
            entity("climate.c", state: "heat", #","current_temperature":21.5"#)])
        XCTAssertEqual(room.summary, "2 lights on · \(EntityFormat.number(21.5))°")
        XCTAssertEqual(Room(id: "x", name: "X", entities: [entity("light.a")]).summary, "Lights off")
        XCTAssertEqual(Room(id: "x", name: "X", entities: [entity("switch.a"), entity("switch.b")]).summary, "2 devices")
        let sensorRoom = Room(id: "x", name: "X", entities: [
            entity("sensor.t", state: "19.8", #","device_class":"temperature""#)])
        XCTAssertEqual(sensorRoom.temperature, 19.8)
    }

    func testSymbolGuessesFromEnglishAndDutchNames() {
        func symbol(_ name: String) -> String { Room(id: "x", name: name, entities: []).symbolName }
        XCTAssertEqual(symbol("Kitchen"), "fork.knife")
        XCTAssertEqual(symbol("Slaapkamer"), "bed.double")
        XCTAssertEqual(symbol("Woonkamer"), "sofa")
        XCTAssertEqual(symbol("Something else"), "house")
        XCTAssertEqual(Room(id: Room.unassignedID, name: "Unassigned", entities: []).symbolName, "questionmark.square.dashed")
    }
}
