import XCTest

/// Geometry of the detection pop-up stack (AppKit coordinates, origin bottom-left).
final class PopUpStackLayoutTests: XCTestCase {

    private let area = CGRect(x: 0, y: 0, width: 2560, height: 1400)
    private let wide: CGFloat = 16.0 / 9.0

    func testVerticalStackGrowsUpFromTheBottomRight() {
        let layout = PopUpStackLayout(corner: .bottomRight, direction: .vertical, size: .medium, area: area)
        let frames = layout.frames(aspects: [wide, wide])
        XCTAssertEqual(frames[0], CGRect(x: 2560 - 16 - 480, y: 16, width: 480, height: 270))
        XCTAssertEqual(frames[1], CGRect(x: 2560 - 16 - 480, y: 16 + 270 + 10, width: 480, height: 270))
    }

    func testTopLeftStacksDownward() {
        let layout = PopUpStackLayout(corner: .topLeft, direction: .vertical, size: .small, area: area)
        let frames = layout.frames(aspects: [wide, wide])
        XCTAssertEqual(frames[0], CGRect(x: 16, y: 1400 - 16 - 180, width: 320, height: 180))
        XCTAssertEqual(frames[1].maxY, frames[0].minY - 10)
    }

    func testVerticalStackSharesAWidthAndFollowsEachShape() {
        let layout = PopUpStackLayout(corner: .bottomRight, direction: .vertical, size: .medium, area: area)
        let frames = layout.frames(aspects: [wide, 4.0 / 3.0])
        XCTAssertEqual(frames.map(\.width), [480, 480])
        XCTAssertEqual(frames.map(\.height), [270, 360])
    }

    func testHorizontalStackSharesAHeight() {
        let layout = PopUpStackLayout(corner: .bottomLeft, direction: .horizontal, size: .medium, area: area)
        let frames = layout.frames(aspects: [wide, 4.0 / 3.0])
        XCTAssertEqual(frames.map(\.height), [270, 270])
        XCTAssertEqual(frames[0], CGRect(x: 16, y: 16, width: 480, height: 270))
        XCTAssertEqual(frames[1], CGRect(x: 16 + 480 + 10, y: 16, width: 360, height: 270))
    }

    func testWrapsIntoAnotherColumnAtTheScreenEdge() {
        // 600 pt tall: two 270-pt windows fit (16 + 270 + 10 + 270 + 16 = 582), a third does not.
        let small = CGRect(x: 100, y: 50, width: 2000, height: 600)
        let layout = PopUpStackLayout(corner: .bottomRight, direction: .vertical, size: .medium, area: small)
        let frames = layout.frames(aspects: [wide, wide, wide])
        XCTAssertEqual(frames[2].minY, frames[0].minY)
        XCTAssertEqual(frames[2].maxX, frames[0].minX - 10)
        for frame in frames { XCTAssertTrue(small.contains(frame)) }
    }

    func testClosingOneClosesTheGap() {
        let layout = PopUpStackLayout(corner: .bottomRight, direction: .vertical, size: .medium, area: area)
        let three = layout.frames(aspects: [wide, wide, wide])
        let two = layout.frames(aspects: [wide, wide])
        // The survivors of a closed first window take the first two slots.
        XCTAssertEqual(Array(three.prefix(2)), two)
    }

    func testAWindowTallerThanTheScreenStillGetsASlot() {
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 200)
        let layout = PopUpStackLayout(corner: .bottomRight, direction: .vertical, size: .large, area: tiny)
        XCTAssertEqual(layout.frames(aspects: [wide, wide]).count, 2)
    }
}
