import CoreGraphics
import Foundation

/// The screen corner detection pop-ups stack out of.
enum PopUpCorner: String, CaseIterable, Codable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    var displayName: String {
        switch self {
        case .topLeft:     return String(localized: "Top left")
        case .topRight:    return String(localized: "Top right")
        case .bottomLeft:  return String(localized: "Bottom left")
        case .bottomRight: return String(localized: "Bottom right")
        }
    }
}

enum PopUpSize: String, CaseIterable, Codable {
    case small, medium, large

    /// Width of a 16:9 pop-up, in points.
    var width: CGFloat {
        switch self {
        case .small:  return 320
        case .medium: return 480
        case .large:  return 640
        }
    }

    var displayName: String {
        switch self {
        case .small:  return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large:  return String(localized: "Large")
        }
    }
}

enum PopUpDirection: String, CaseIterable, Codable {
    case vertical, horizontal

    var displayName: String {
        switch self {
        case .vertical:   return String(localized: "Vertical")
        case .horizontal: return String(localized: "Horizontal")
        }
    }
}

/// Where each detection pop-up goes: a stack growing out of one screen corner,
/// in arrival order, wrapping into a further column (or row) at the screen
/// edge. Pure geometry in AppKit screen coordinates (origin bottom-left).
struct PopUpStackLayout: Equatable {
    var corner: PopUpCorner = .bottomRight
    var direction: PopUpDirection = .vertical
    var size: PopUpSize = .medium
    /// The usable area of the target display (its `visibleFrame`).
    var area: CGRect
    var inset: CGFloat = 16
    var gap: CGFloat = 10

    static let referenceAspect: CGFloat = 16.0 / 9.0

    /// One frame per window, in stack order; `aspects` are width ÷ height.
    /// A vertical stack gives every window the same width; a horizontal one
    /// the same height, so a taller picture (a doorbell) doesn't break the row.
    func frames(aspects: [CGFloat]) -> [CGRect] {
        let sizes = aspects.map(windowSize)
        var frames: [CGRect] = []
        var along: CGFloat = 0   // distance from the corner along the stack
        var line: CGFloat = 0    // offset of the current column / row
        var lineThickness: CGFloat = 0
        let isVertical = direction == .vertical
        let limit = (isVertical ? area.height : area.width) - 2 * inset

        for size in sizes {
            let length = isVertical ? size.height : size.width
            let thickness = isVertical ? size.width : size.height
            if along > 0, along + length > limit {
                line += lineThickness + gap
                along = 0
                lineThickness = 0
            }
            let dx = isVertical ? line : along
            let dy = isVertical ? along : line
            let x = corner.isLeft ? area.minX + inset + dx : area.maxX - inset - dx - size.width
            let y = corner.isTop ? area.maxY - inset - dy - size.height : area.minY + inset + dy
            frames.append(CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height))
            along += length + gap
            lineThickness = max(lineThickness, thickness)
        }
        return frames
    }

    private func windowSize(aspect: CGFloat) -> CGSize {
        let ar = aspect > 0 ? aspect : Self.referenceAspect
        switch direction {
        case .vertical:
            return CGSize(width: size.width, height: (size.width / ar).rounded())
        case .horizontal:
            let height = (size.width / Self.referenceAspect).rounded()
            return CGSize(width: (height * ar).rounded(), height: height)
        }
    }
}
