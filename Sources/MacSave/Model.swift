import Foundation

struct Rect: Codable, Equatable {
    var x: Double, y: Double, width: Double, height: Double

    func close(to o: Rect, tolerance: Double = 4) -> Bool {
        abs(x - o.x) <= tolerance && abs(y - o.y) <= tolerance
            && abs(width - o.width) <= tolerance && abs(height - o.height) <= tolerance
    }
}

struct TabInfo: Codable {
    var title: String
    var url: String?
    var detail: String?
    var active: Bool = false
    var id: Int?
}

struct WindowInfo: Codable {
    var windowID: UInt32?
    var app: String
    var bundleID: String?
    var pid: Int32
    var title: String
    var bounds: Rect?
    var minimized = false
    var appHidden = false
    var focused = false
    var spaceIDs: [UInt64] = []
    var tabs: [TabInfo] = []
    var note: String?
    var zOrder = Int.max
    var scriptID: Int?
}

struct SpaceInfo: Codable {
    var id: UInt64
    var display: Int
    var desktopNumber: Int?
    var fullscreen: Bool
    var current: Bool
}

struct Snapshot: Codable {
    var date: Date
    var displayCount: Int
    var spaces: [SpaceInfo]
    var windows: [WindowInfo]
    var warnings: [String]

    var tabCount: Int { windows.reduce(0) { $0 + $1.tabs.count } }

    func space(_ id: UInt64) -> SpaceInfo? { spaces.first { $0.id == id } }

    func label(for space: SpaceInfo) -> String {
        var name: String
        if space.fullscreen {
            let w = windows.first { $0.spaceIDs == [space.id] }
            name = "Fullscreen" + (w.map { ": \($0.app)" } ?? "")
        } else {
            name = "Desktop \(space.desktopNumber ?? 0)"
        }
        if displayCount > 1 { name = "Display \(space.display + 1) · " + name }
        if space.current { name += " (current)" }
        return name
    }
}
