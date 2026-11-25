import XCTest

/// Drives `DetectionPopUpCoordinator` with a recording window manager: which
/// detections open a window, and what keeps it from reopening.
@MainActor
final class DetectionPopUpCoordinatorTests: XCTestCase {

    private final class Windows: DetectionPopUpWindows {
        var open: Set<String> = []
        var popUpCount = 0
        var secondaryLens: Set<String> = []
        var onPopUpClosedByUser: ((String) -> Void)?

        func popUp(_ camera: Camera, showingSecondaryLens: Bool) {
            if showingSecondaryLens { secondaryLens.insert(camera.id) }
            guard !open.contains(camera.id) else { return }
            open.insert(camera.id)
            popUpCount += 1
        }
        func dismissPopUp(_ cameraId: String) { open.remove(cameraId) }
        func userCloses(_ cameraId: String) {
            open.remove(cameraId)
            onPopUpClosedByUser?(cameraId)
        }
    }

    private final class NoSecrets: SecretStoring {
        func get(_ account: String) -> String? { nil }
        func set(_ value: String, account: String) -> Bool { true }
        func remove(_ account: String) -> Bool { true }
    }

    private var suiteName = ""
    private var settings: AppSettings!
    private var windows: Windows!
    private var coordinator: DetectionPopUpCoordinator!
    private var sounds: [String] = []

    override func setUp() async throws {
        suiteName = "DetectionPopUpCoordinatorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = AppSettings(defaults: defaults, secrets: NoSecrets())
        windows = Windows()
        let cameras = try ["cam", "other"].map { id in
            try JSONDecoder().decode(Camera.self, from: Data(#"{"id":"\#(id)","name":"Cam","state":"CONNECTED"}"#.utf8))
        }
        coordinator = DetectionPopUpCoordinator(
            windows: windows, settings: settings,
            camera: { id in cameras.first { $0.id == id } },
            playSound: { [unowned self] name in self.sounds.append(name) }
        )
        settings.setPopUpEnabled(true, for: "cam")
        settings.setPopUpTriggers([.person], for: "cam")
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func send(_ id: String, camera: String = "cam", type: String = "smartDetectZone",
                      types: [String] = ["person"], ended: Bool = false) {
        let typeList = types.map { "\"\($0)\"" }.joined(separator: ",")
        let end = ended ? #","end":2"# : ""
        coordinator.handle(Data("""
        {"item":{"id":"\(id)","modelKey":"event","type":"\(type)","start":1\(end),
                 "device":"\(camera)","smartDetectTypes":[\(typeList)]},"type":"update"}
        """.utf8))
    }

    func testChosenDetectionOpensTheWindow() {
        send("e1", types: [])           // announced, not yet classified
        XCTAssertTrue(windows.open.isEmpty)
        send("e1")
        XCTAssertEqual(windows.open, ["cam"])
    }

    func testOtherDetectionsAndCamerasAreIgnored() {
        send("e1", types: ["vehicle"])
        send("e2", type: "motion", types: [])
        send("e3", camera: "other")      // pop-ups not enabled for this camera
        send("e4", camera: "missing")    // not in the grid
        XCTAssertTrue(windows.open.isEmpty)
    }

    func testPausedOrDisabledOpensNothing() {
        settings.popUpsPaused = true
        send("e1")
        settings.popUpsPaused = false
        settings.setPopUpEnabled(false, for: "cam")
        send("e2")
        XCTAssertTrue(windows.open.isEmpty)
    }

    func testClosingAPopUpKeepsThatDetectionDismissed() {
        send("e1")
        windows.userCloses("cam")
        send("e1")                       // the same detection keeps updating
        XCTAssertTrue(windows.open.isEmpty)
        send("e2")                       // a new one opens it again
        XCTAssertEqual(windows.open, ["cam"])
    }

    func testEndOfADismissedDetectionDoesNotReopen() {
        send("e1")
        windows.userCloses("cam")
        send("e1", ended: true)
        XCTAssertTrue(windows.open.isEmpty)
        XCTAssertEqual(windows.popUpCount, 1)
    }

    func testMotionOpensTheWindowWhenChosen() {
        settings.setPopUpTriggers([.motion], for: "cam")
        // Motion events carry no smartDetectTypes field at all.
        coordinator.handle(Data(#"{"type":"add","item":{"id":"m1","modelKey":"event","type":"motion","start":1,"device":"cam"}}"#.utf8))
        XCTAssertEqual(windows.open, ["cam"])
    }

    func testUpdatesAfterTheEndDoNotReopen() {
        send("e1")
        send("e1", ended: true)
        windows.dismissPopUp("cam")      // what the linger timer does
        send("e1", ended: true)          // late metadata update for the finished event
        XCTAssertTrue(windows.open.isEmpty)
        XCTAssertEqual(windows.popUpCount, 1)
    }

    func testPackageDetectionAsksForTheSecondLens() {
        settings.setPopUpTriggers([.person, .package], for: "cam")
        send("e1")
        XCTAssertTrue(windows.secondaryLens.isEmpty)
        // A package seen while the window is already up adds the inset to it.
        send("e2", types: ["package"])
        XCTAssertEqual(windows.secondaryLens, ["cam"])
        XCTAssertEqual(windows.popUpCount, 1)
    }

    func testSoundPlaysOncePerDetectionAndOnlyWhenChosen() {
        send("e1")
        XCTAssertEqual(sounds, [])       // silent by default
        settings.popUpSound = "Glass"
        send("e2")
        send("e2")                       // the same detection updating
        send("e2", ended: true)
        send("e3", types: ["vehicle"])   // not a chosen trigger
        XCTAssertEqual(sounds, ["Glass"])
    }

    func testDetectionReportedOnlyOnceOverStillShows() {
        send("e1", ended: true)
        XCTAssertEqual(windows.open, ["cam"])
    }
}
