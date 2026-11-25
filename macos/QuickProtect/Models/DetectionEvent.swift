import Foundation

/// A kind of detection the user can choose to be alerted by. Coarser than the
/// controller's own types: its `face` counts as a person and `licensePlate`
/// as a vehicle, since nobody wants those as separate switches.
enum DetectionTrigger: String, CaseIterable, Codable {
    case person, vehicle, animal, package, ring, motion, sound

    /// What a camera's pop-ups react to until the user chooses.
    static let defaults: Set<DetectionTrigger> = [.person, .package, .ring]

    var displayName: String {
        switch self {
        case .person:  return String(localized: "Person")
        case .vehicle: return String(localized: "Vehicle")
        case .animal:  return String(localized: "Animal")
        case .package: return String(localized: "Package")
        case .ring:    return String(localized: "Doorbell ring")
        case .motion:  return String(localized: "Motion")
        case .sound:   return String(localized: "Sound")
        }
    }

    /// The trigger a controller smart-detect object type belongs to.
    static func forObjectType(_ type: String) -> DetectionTrigger? {
        switch type {
        case "person", "face":           return .person
        case "vehicle", "licensePlate":  return .vehicle
        case "animal":                   return .animal
        case "package":                  return .package
        default:                         return nil
        }
    }

    /// The triggers an event satisfies, from its `type` and `smartDetectTypes`.
    /// A smart detection is announced before it is classified (the first
    /// message carries no types), so it matches nothing until an update names
    /// what was seen.
    static func matching(eventType: String, smartDetectTypes: [String]) -> Set<DetectionTrigger> {
        switch eventType {
        case "motion":           return [.motion]
        case "ring":             return [.ring]
        case "smartAudioDetect": return smartDetectTypes.isEmpty ? [] : [.sound]
        default:
            guard eventType.hasPrefix("smartDetect") else { return [] }
            return Set(smartDetectTypes.compactMap(forObjectType))
        }
    }

    /// The triggers worth offering for a camera, in display order. A camera
    /// whose capabilities are unknown is offered everything.
    static func supported(by camera: Camera) -> [DetectionTrigger] {
        guard let objects = camera.detectableObjects else { return allCases }
        var supported: Set<DetectionTrigger> = [.motion]
        supported.formUnion(objects.compactMap(forObjectType))
        if camera.detectsSound { supported.insert(.sound) }
        // The Integration API has no doorbell flag; package detection and
        // the package lens only exist on doorbells.
        if supported.contains(.package) || camera.secondaryLens != nil { supported.insert(.ring) }
        return allCases.filter(supported.contains)
    }
}

/// One message from the Integration API event stream that describes a
/// camera event. Every message repeats the whole event; `end` appears once
/// the detection is over.
struct ProtectEvent: Equatable {
    let id: String
    let type: String
    let cameraID: String
    let smartDetectTypes: [String]
    let isEnded: Bool

    var triggers: Set<DetectionTrigger> {
        DetectionTrigger.matching(eventType: type, smartDetectTypes: smartDetectTypes)
    }

    /// Nil for anything that isn't a camera event (device updates, malformed data).
    static func parse(_ data: Data) -> ProtectEvent? {
        struct Envelope: Decodable {
            struct Item: Decodable {
                let id: String
                let modelKey: String?
                let type: String
                let device: String
                let end: Double?
                let smartDetectTypes: [String]?
            }
            let item: Item
        }
        guard let item = (try? JSONDecoder().decode(Envelope.self, from: data))?.item,
              item.modelKey == "event" else { return nil }
        return ProtectEvent(id: item.id, type: item.type, cameraID: item.device,
                            smartDetectTypes: item.smartDetectTypes ?? [], isEnded: item.end != nil)
    }
}
