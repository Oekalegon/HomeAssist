import XCTest
@testable import HomeAssist

final class LiveUpdatesTests: XCTestCase {
    private func entity(_ id: String, _ name: String, _ state: String = "off") throws -> HAEntity {
        let json = #"{"entity_id":"\#(id)","state":"\#(state)","attributes":{"friendly_name":"\#(name)"}}"#
        return try JSONDecoder().decode(HAEntity.self, from: Data(json.utf8))
    }

    func testParsesAuthMessages() throws {
        XCTAssertEqual(try HAWebSocketMessage.parse(Data(#"{"type":"auth_required","ha_version":"2026.1"}"#.utf8)), .authRequired)
        XCTAssertEqual(try HAWebSocketMessage.parse(Data(#"{"type":"auth_ok"}"#.utf8)), .authOk)
        XCTAssertEqual(try HAWebSocketMessage.parse(Data(#"{"type":"auth_invalid","message":"bad"}"#.utf8)), .authInvalid("bad"))
    }

    func testParsesResultAndUnknown() throws {
        XCTAssertEqual(try HAWebSocketMessage.parse(Data(#"{"id":1,"type":"result","success":true,"result":null}"#.utf8)),
                       .result(id: 1, success: true))
        XCTAssertEqual(try HAWebSocketMessage.parse(Data(#"{"id":2,"type":"pong"}"#.utf8)), .other)
    }

    func testParsesStateChangedEvent() throws {
        let json = #"{"id":1,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.kitchen","old_state":null,"new_state":{"entity_id":"light.kitchen","state":"on","attributes":{"friendly_name":"Kitchen"}}}}}"#
        guard case .stateChanged(let change) = try HAWebSocketMessage.parse(Data(json.utf8)) else {
            return XCTFail("expected stateChanged")
        }
        XCTAssertEqual(change.entityId, "light.kitchen")
        XCTAssertEqual(change.newState?.state, "on")
    }

    func testParsesRemovedEntity() throws {
        let json = #"{"id":1,"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"light.gone","new_state":null}}}"#
        XCTAssertEqual(try HAWebSocketMessage.parse(Data(json.utf8)),
                       .stateChanged(StateChange(entityId: "light.gone", newState: nil)))
    }

    func testApplyingReplacesInsertsAndRemoves() throws {
        let a = try entity("light.a", "A"), c = try entity("light.c", "C")
        var list = [a, c]

        list = list.applying(StateChange(entityId: "light.a", newState: try entity("light.a", "A", "on")))
        XCTAssertEqual(list.map(\.state), ["on", "off"])

        list = list.applying(StateChange(entityId: "light.b", newState: try entity("light.b", "B")))
        XCTAssertEqual(list.map(\.entityId), ["light.a", "light.b", "light.c"])

        list = list.applying(StateChange(entityId: "light.b", newState: nil))
        XCTAssertEqual(list.map(\.entityId), ["light.a", "light.c"])

        XCTAssertEqual(list.applying(StateChange(entityId: "light.zzz", newState: nil)), list)
    }

    func testWebSocketURLMapsSchemeAndKeepsPrefix() {
        XCTAssertEqual(HAWebSocketClient.webSocketURL(from: URL(string: "http://ha.local:8123")!)?.absoluteString,
                       "ws://ha.local:8123/api/websocket")
        XCTAssertEqual(HAWebSocketClient.webSocketURL(from: URL(string: "https://example.com/ha")!)?.absoluteString,
                       "wss://example.com/ha/api/websocket")
    }

    func testApplyingBatchAppliesInOrderAndLastChangeWins() throws {
        let list = [try entity("light.a", "A")]
        let result = list.applying([
            StateChange(entityId: "light.a", newState: try entity("light.a", "A", "on")),
            StateChange(entityId: "light.a", newState: try entity("light.a", "A", "off")),
            StateChange(entityId: "light.b", newState: try entity("light.b", "B")),
            StateChange(entityId: "light.b", newState: nil),
        ])
        XCTAssertEqual(result.map(\.entityId), ["light.a"])
        XCTAssertEqual(result.first?.state, "off")
    }

    func testSortIsStableForEqualNames() throws {
        let list = [try entity("light.z", "Same"), try entity("light.a", "Same")]
        XCTAssertEqual(list.sortedForDisplay().map(\.entityId), ["light.a", "light.z"])
    }

    func testGroupedByDomainFiltersAndSorts() throws {
        let list = [try entity("switch.fan", "Fan"), try entity("light.lamp", "Lamp"),
                    try entity("light.desk", "Desk")]
        let all = list.groupedByDomain()
        XCTAssertEqual(all.map(\.domain), ["light", "switch"])
        XCTAssertEqual(all[0].entities.map(\.entityId), ["light.lamp", "light.desk"]) // input order kept
        XCTAssertEqual(list.groupedByDomain(matching: "des").flatMap(\.entities).map(\.entityId), ["light.desk"])
        XCTAssertTrue(list.groupedByDomain(matching: "nothing").isEmpty)
    }
}
