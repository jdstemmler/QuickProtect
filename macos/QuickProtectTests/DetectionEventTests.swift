import XCTest

/// Tests for the event-stream parsing and the detection → trigger mapping
/// behind detection pop-ups. Payloads are the shapes a UNVR actually sends.
final class DetectionEventTests: XCTestCase {

    private func event(_ json: String) -> ProtectEvent? { ProtectEvent.parse(Data(json.utf8)) }

    func testParsesAnEventInProgress() {
        let parsed = event("""
        {"item":{"id":"e1","modelKey":"event","type":"smartDetectZone","start":1795628678737,
                 "device":"cam1","smartDetectTypes":["person"]},"type":"update"}
        """)
        XCTAssertEqual(parsed, ProtectEvent(id: "e1", type: "smartDetectZone", cameraID: "cam1",
                                            smartDetectTypes: ["person"], isEnded: false))
        XCTAssertEqual(parsed?.triggers, [.person])
    }

    func testEndMarksTheEventOver() {
        let parsed = event("""
        {"item":{"id":"e1","modelKey":"event","type":"motion","start":1,"end":2,"device":"cam1"},"type":"update"}
        """)
        XCTAssertEqual(parsed?.isEnded, true)
        XCTAssertEqual(parsed?.triggers, [.motion])
    }

    func testIgnoresNonEventAndMalformedMessages() {
        XCTAssertNil(event(#"{"item":{"id":"c1","modelKey":"camera","type":"x","device":"c1"},"type":"update"}"#))
        XCTAssertNil(event(#"{"hello":true}"#))
        XCTAssertNil(event("not json"))
    }

    func testUnclassifiedSmartDetectionMatchesNothingYet() {
        // The first message of a smart detection carries no types.
        XCTAssertEqual(DetectionTrigger.matching(eventType: "smartDetectZone", smartDetectTypes: []), [])
        XCTAssertEqual(DetectionTrigger.matching(eventType: "smartAudioDetect", smartDetectTypes: []), [])
        XCTAssertEqual(DetectionTrigger.matching(eventType: "smartAudioDetect", smartDetectTypes: ["alrmSpeak"]), [.sound])
    }

    func testObjectTypesFoldIntoTriggers() {
        XCTAssertEqual(DetectionTrigger.matching(eventType: "smartDetectLine",
                                                 smartDetectTypes: ["face", "licensePlate", "package", "animal"]),
                       [.person, .vehicle, .package, .animal])
        XCTAssertEqual(DetectionTrigger.matching(eventType: "ring", smartDetectTypes: []), [.ring])
        XCTAssertEqual(DetectionTrigger.matching(eventType: "somethingNew", smartDetectTypes: ["person"]), [])
    }

    func testSupportedTriggersFollowTheCamerasCapabilities() throws {
        func camera(_ flags: String) throws -> Camera {
            try JSONDecoder().decode(Camera.self, from: Data("""
            {"id":"c","name":"Cam","state":"CONNECTED","featureFlags":\(flags)}
            """.utf8))
        }
        let doorbell = try camera(#"{"smartDetectTypes":["person","vehicle","animal","package"],"smartDetectAudioTypes":["alrmSpeak"]}"#)
        XCTAssertEqual(DetectionTrigger.supported(by: doorbell), [.person, .vehicle, .animal, .package, .ring, .motion, .sound])

        let basic = try camera(#"{"smartDetectTypes":[],"smartDetectAudioTypes":[]}"#)
        XCTAssertEqual(DetectionTrigger.supported(by: basic), [.motion])

        // Capabilities unknown (no feature flags in the payload): offer everything.
        let unknown = try JSONDecoder().decode(Camera.self, from: Data(#"{"id":"c","name":"Cam"}"#.utf8))
        XCTAssertEqual(DetectionTrigger.supported(by: unknown), DetectionTrigger.allCases)
    }

    func testRecentIDsForgetsTheOldest() {
        var ids = RecentIDs(capacity: 2)
        ids.insert("a"); ids.insert("b"); ids.insert("a"); ids.insert("c")
        XCTAssertFalse(ids.contains("a"))
        XCTAssertTrue(ids.contains("b"))
        XCTAssertTrue(ids.contains("c"))
    }
}
