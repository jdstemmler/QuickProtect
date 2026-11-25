import Foundation

// MARK: - Per-camera detection pop-ups: on/off and which detections trigger one.

extension AppSettings {

    /// Whether a detection on this camera opens its floating window. Off
    /// until the user turns it on; the dict only holds explicit choices.
    func popUpEnabled(for id: String) -> Bool {
        let dict = defaults.dictionary(forKey: Keys.popUpCameras) as? [String: Bool]
        return dict?[id] ?? false
    }

    func setPopUpEnabled(_ on: Bool, for id: String) {
        var dict = (defaults.dictionary(forKey: Keys.popUpCameras) as? [String: Bool]) ?? [:]
        dict[id] = on
        defaults.set(dict, forKey: Keys.popUpCameras)
        objectWillChange.send()
    }

    /// The detections that open this camera's window. Kept while pop-ups are
    /// switched off for the camera, so turning them back on restores the choice.
    func popUpTriggers(for id: String) -> Set<DetectionTrigger> {
        guard let dict = defaults.dictionary(forKey: Keys.popUpTriggers) as? [String: [String]],
              let raw = dict[id] else { return DetectionTrigger.defaults }
        return Set(raw.compactMap(DetectionTrigger.init(rawValue:)))
    }

    func setPopUpTriggers(_ triggers: Set<DetectionTrigger>, for id: String) {
        var dict = (defaults.dictionary(forKey: Keys.popUpTriggers) as? [String: [String]]) ?? [:]
        dict[id] = triggers.map(\.rawValue).sorted()
        defaults.set(dict, forKey: Keys.popUpTriggers)
        objectWillChange.send()
    }
}
