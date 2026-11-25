import AppKit
import Combine

/// The window operations detection pop-ups need. `PinnedWindowManager` is the
/// real one; keeping the coordinator off the view layer lets tests drive it.
@MainActor
protocol DetectionPopUpWindows: AnyObject {
    /// Shows a detection: opens a temporary window, or, when the user has
    /// the camera pinned, highlights that window instead. Repeated calls for
    /// a window already showing change nothing.
    /// `showingSecondaryLens` adds the camera's second lens (a doorbell's
    /// package camera) as an inset, also on a window that is already open.
    func popUp(_ camera: Camera, showingSecondaryLens: Bool)
    /// The detection is over: closes the temporary window, or takes the
    /// highlight and inset off a pinned one, which stays open.
    func dismissPopUp(_ cameraId: String)
    /// Called when the user closes a window that was showing a detection.
    var onPopUpClosedByUser: ((String) -> Void)? { get set }
}

/// Opens a camera's floating window when the controller reports a detection
/// the user asked to be shown, and closes it again shortly after the
/// detection ends. Windows the user pinned themselves are never touched.
@MainActor
final class DetectionPopUpCoordinator {
    private let windows: any DetectionPopUpWindows
    private let settings: AppSettings
    /// The camera for an event's device id; nil when it isn't in the grid.
    private let camera: (String) -> Camera?
    private var subscription: AnyCancellable?

    /// Matching detections still in progress, per camera.
    private var activeEvents: [String: Set<String>] = [:]
    /// Detections whose pop-up the user closed: they must not reopen it.
    private var suppressedEvents: Set<String> = []
    /// Detections already over. The controller keeps sending updates for an
    /// event after it ends; without this they would reopen the window.
    private var finishedEvents = RecentIDs(capacity: 256)
    /// Detections already announced with the sound, so their updates stay quiet.
    private var announcedEvents = RecentIDs(capacity: 256)
    /// Plays the named alert sound.
    private let playSound: (String) -> Void
    private var closeTasks: [String: Task<Void, Never>] = [:]

    /// Debug aid: launch with QUICKPROTECT_POPUP_SECONDARY_LENS=1 to show the
    /// second-lens inset on every pop-up, so it can be checked without
    /// waiting for a parcel.
    static let alwaysShowSecondaryLens =
        ProcessInfo.processInfo.environment["QUICKPROTECT_POPUP_SECONDARY_LENS"] == "1"

    /// A pop-up whose detection never reports an end closes after this long.
    static let maxOpenSeconds = 300

    init(windows: any DetectionPopUpWindows, settings: AppSettings, camera: @escaping (String) -> Camera?,
         playSound: @escaping (String) -> Void = { NSSound(named: $0)?.play() }) {
        self.windows = windows
        self.settings = settings
        self.camera = camera
        self.playSound = playSound
        windows.onPopUpClosedByUser = { [weak self] cameraID in self?.userClosed(cameraID) }
    }

    /// Follows every site's event stream on `hub`.
    convenience init(hub: ProtectHub, windows: any DetectionPopUpWindows, settings: AppSettings = .shared) {
        self.init(windows: windows, settings: settings) { [weak hub] id in
            hub?.cameras.first { $0.id == id }
        }
        subscription = hub.eventMessages
            .receive(on: RunLoop.main)
            .sink { [weak self] message in self?.handle(message.data) }
    }

    func handle(_ data: Data) {
        guard let event = ProtectEvent.parse(data), !finishedEvents.contains(event.id) else { return }
        let cameraID = event.cameraID

        if event.isEnded {
            finishedEvents.insert(event.id)
            // The user already closed this detection's window; its end must
            // not bring the window back for the linger time.
            if suppressedEvents.remove(event.id) != nil { return }
            if activeEvents[cameraID]?.remove(event.id) != nil {
                if activeEvents[cameraID]?.isEmpty == true {
                    activeEvents[cameraID] = nil
                    scheduleClose(cameraID, after: settings.popUpLingerSeconds)
                }
                return
            }
        }

        guard !settings.popUpsPaused,
              settings.popUpEnabled(for: cameraID),
              !suppressedEvents.contains(event.id),
              !event.triggers.isDisjoint(with: settings.popUpTriggers(for: cameraID)),
              let camera = camera(cameraID), camera.isOnline else { return }

        RTSPClient.log("[PopUp] \(camera.name): \(event.type) \(event.smartDetectTypes)")
        if announcedEvents.insert(event.id), !settings.popUpSound.isEmpty {
            playSound(settings.popUpSound)
        }
        // A package on the step is seen by the downward lens, not the main one.
        windows.popUp(camera, showingSecondaryLens: event.triggers.contains(.package) || Self.alwaysShowSecondaryLens)
        if event.isEnded {
            // Reported only once it was over: show it for the linger time,
            // unless another detection is keeping the window open.
            if activeEvents[cameraID] == nil {
                scheduleClose(cameraID, after: settings.popUpLingerSeconds)
            }
        } else {
            activeEvents[cameraID, default: []].insert(event.id)
            scheduleClose(cameraID, after: Self.maxOpenSeconds)
        }
    }

    private func scheduleClose(_ cameraID: String, after seconds: Int) {
        closeTasks[cameraID]?.cancel()
        closeTasks[cameraID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return // superseded by a newer detection, or closed by the user
            }
            self?.close(cameraID)
        }
    }

    private func close(_ cameraID: String) {
        closeTasks[cameraID] = nil
        activeEvents[cameraID] = nil
        windows.dismissPopUp(cameraID)
    }

    /// The user dismissed the pop-up: the detections behind it stay dismissed.
    private func userClosed(_ cameraID: String) {
        closeTasks.removeValue(forKey: cameraID)?.cancel()
        suppressedEvents.formUnion(activeEvents.removeValue(forKey: cameraID) ?? [])
    }
}

/// A bounded set of ids that forgets the oldest once full.
struct RecentIDs {
    private let capacity: Int
    private var order: [String] = []
    private var members: Set<String> = []

    init(capacity: Int) { self.capacity = max(1, capacity) }

    func contains(_ id: String) -> Bool { members.contains(id) }

    /// Returns true when the id was not already present.
    @discardableResult
    mutating func insert(_ id: String) -> Bool {
        guard members.insert(id).inserted else { return false }
        order.append(id)
        if order.count > capacity { members.remove(order.removeFirst()) }
        return true
    }
}
