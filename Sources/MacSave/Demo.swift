import AppKit

/// Fake snapshot + synthetic window images for screenshots and trying the UI (`MacSave --demo`).
enum Demo {
    static let canvas = CGRect(x: 0, y: 0, width: 1440, height: 900)

    static func snapshot() -> Snapshot {
        var z = 0
        var nextID: UInt32 = 900_001
        func win(_ app: String, _ bundle: String, space: UInt64, title: String = "", _ b: (Double, Double, Double, Double),
                 tabs: [TabInfo] = [], note: String? = nil, minimized: Bool = false, focused: Bool = false) -> WindowInfo {
            defer { z += 1; nextID += 1 }
            return WindowInfo(windowID: nextID, app: app, bundleID: bundle, pid: -1, title: title,
                              bounds: Rect(x: b.0, y: b.1, width: b.2, height: b.3), minimized: minimized,
                              focused: focused, spaceIDs: [space], tabs: tabs, note: note, zOrder: z)
        }
        func web(_ t: String, _ u: String, active: Bool = false) -> TabInfo { TabInfo(title: t, url: u, active: active) }
        func file(_ t: String, _ d: String, active: Bool = false) -> TabInfo { TabInfo(title: t, detail: d, active: active) }

        let chrome = "com.google.Chrome", safari = "com.apple.Safari", iterm = "com.googlecode.iterm2"
        let windows = [
            win("Cursor", "com.todesktop.230313mzl4w4u92", space: 102, title: "ForecastView.swift — weather-app", (0, 25, 1010, 875),
                tabs: [file("ForecastView.swift", "Sources/App/ForecastView.swift", active: true),
                       file("WeatherAPI.swift", "Sources/App/WeatherAPI.swift"),
                       file("Package.swift", "Package.swift"),
                       file("README.md", "README.md")],
                note: "weather-app", focused: true),
            win("Safari", safari, space: 102, (1010, 25, 430, 620),
                tabs: [web("Open-Meteo: Free Weather API", "https://open-meteo.com/en/docs", active: true),
                       web("Hacker News", "https://news.ycombinator.com/"),
                       web("Spaces (software) - Wikipedia", "https://en.wikipedia.org/wiki/Spaces_(software)")]),
            win("iTerm2", iterm, space: 102, (1010, 645, 430, 255),
                tabs: [file("swift build", "~/code/weather-app · swift build", active: true),
                       file("zsh", "~/code/weather-app")]),
            win("Notes", "com.apple.Notes", space: 102, title: "Groceries & errands", (300, 120, 700, 560), minimized: true),

            win("Google Chrome", chrome, space: 101, (30, 40, 920, 840),
                tabs: [web("Concurrency | The Swift Programming Language", "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/", active: true),
                       web("ScreenCaptureKit | Apple Developer Documentation", "https://developer.apple.com/documentation/screencapturekit"),
                       web("AXUIElement.h | Apple Developer Documentation", "https://developer.apple.com/documentation/applicationservices/axuielement_h"),
                       web("apple/swift-argument-parser", "https://github.com/apple/swift-argument-parser"),
                       web("Mission Control - Wikipedia", "https://en.wikipedia.org/wiki/Mission_Control_(macOS)")]),
            win("iTerm2", iterm, space: 101, (970, 40, 450, 520),
                tabs: [file("npm run dev", "~/code/blog · npm run dev", active: true),
                       file("htop", "~ · htop"),
                       file("zsh", "~/code/blog/posts")]),

            win("Finder", "com.apple.finder", space: 103, (80, 90, 820, 520),
                tabs: [file("Downloads", "~/Downloads", active: true), file("Photos 2026", "~/Pictures/Photos 2026")]),
            win("Preview", "com.apple.Preview", space: 103, title: "trail-map.pdf", (560, 160, 820, 700)),
            win("Google Chrome", chrome, space: 103, (200, 60, 1000, 800),
                tabs: [web("Shakshouka - Wikipedia", "https://en.wikipedia.org/wiki/Shakshouka", active: true),
                       web("Sourdough - Wikipedia", "https://en.wikipedia.org/wiki/Sourdough")],
                minimized: true),

            win("Sublime Text", "com.sublimetext.4", space: 104, (180, 70, 1080, 760),
                tabs: [file("todo.txt", "~/notes/todo.txt", active: true),
                       file("ideas.md", "~/notes/ideas.md"),
                       file("reading-list.md", "~/notes/reading-list.md")],
                note: "notes"),
            win("Music", "com.apple.Music", space: 104, title: "Music", (420, 200, 900, 600), minimized: true),
        ]
        let spaces = (1...4).map { i in
            SpaceInfo(id: UInt64(100 + i), display: 0, desktopNumber: i, fullscreen: false, current: i == 2)
        }
        let date = DateComponents(calendar: .current, year: 2026, month: 11, day: 16, hour: 12, minute: 33).date ?? Date()
        return Snapshot(date: date, displayCount: 1, spaces: spaces, windows: windows, warnings: [])
    }

    // MARK: Synthetic window images

    static func images(_ s: Snapshot) -> [CGWindowID: NSImage] {
        var out: [CGWindowID: NSImage] = [:]
        for w in s.windows { if let id = w.windowID, let b = w.bounds { out[id] = image(w, size: NSSize(width: b.width, height: b.height)) } }
        return out
    }

    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: a)
    }

    private static func text(_ s: String, _ p: NSPoint, size: CGFloat = 12, color: NSColor, mono: Bool = false, weight: NSFont.Weight = .regular) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func box(_ r: NSRect, _ c: NSColor, radius: CGFloat = 0) {
        c.setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    }

    private static func trafficLights(_ y: CGFloat) {
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            box(NSRect(x: 14 + CGFloat(i) * 20, y: y, width: 12, height: 12), hex(UInt32(c)), radius: 6)
        }
    }

    /// Paragraph-ish grey bars, deterministic per seed.
    private static func lines(in r: NSRect, seed: Int, color: NSColor, height: CGFloat = 8, gap: CGFloat = 16) {
        var y = r.minY, i = seed
        while y + height <= r.maxY {
            i = (i &* 1103515245 &+ 12345) & 0x7fffffff
            let frac = 0.45 + Double(i % 50) / 100
            if i % 7 != 0 { box(NSRect(x: r.minX, y: y, width: r.width * frac, height: height), color, radius: height / 2) }
            y += gap
        }
    }

    static func image(_ w: WindowInfo, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            let clip = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            clip.addClip()
            let seed = Int(w.windowID ?? 1)
            let b = w.bundleID ?? ""
            if b == "com.google.Chrome" || b == "com.apple.Safari" {
                browser(w, rect, seed: seed)
            } else if b.contains("iterm") {
                terminal(w, rect)
            } else if b.contains("todesktop") || b.contains("sublime") {
                editor(w, rect, seed: seed)
            } else if b == "com.apple.finder" {
                finder(w, rect)
            } else {
                document(w, rect, seed: seed)
            }
            return true
        }
    }

    private static func browser(_ w: WindowInfo, _ r: NSRect, seed: Int) {
        box(r, .white)
        box(NSRect(x: 0, y: 0, width: r.width, height: 74), hex(0xDEE1E6))
        trafficLights(12)
        var x: CGFloat = 86
        for t in w.tabs.prefix(Int(max(1, (r.width - 90) / 170))) {
            if t.active { box(NSRect(x: x, y: 6, width: 164, height: 30), .white, radius: 8) }
            text(String(t.title.prefix(20)), NSPoint(x: x + 12, y: 13), size: 11, color: hex(0x3C4043))
            x += 168
        }
        box(NSRect(x: 0, y: 36, width: r.width, height: 38), .white)
        box(NSRect(x: 90, y: 42, width: r.width - 110, height: 26), hex(0xF1F3F4), radius: 13)
        let url = w.tabs.first(where: \.active)?.url ?? ""
        text(url.replacingOccurrences(of: "https://", with: ""), NSPoint(x: 104, y: 47), size: 11, color: hex(0x5F6368))
        let accent = [0x4C6EF5, 0xF08C00, 0x2F9E44, 0xAE3EC9][seed % 4]
        box(NSRect(x: 40, y: 100, width: r.width - 80, height: 34), hex(UInt32(accent), 0.85), radius: 6)
        let title = w.tabs.first(where: \.active)?.title ?? ""
        text(String(title.prefix(60)), NSPoint(x: 40, y: 150), size: 22, color: hex(0x202124), weight: .semibold)
        box(NSRect(x: r.width - 260, y: 200, width: 220, height: 160), hex(UInt32(accent), 0.18), radius: 8)
        lines(in: NSRect(x: 40, y: 200, width: r.width - 340, height: r.height - 220), seed: seed, color: hex(0xD5D8DC))
    }

    private static func terminal(_ w: WindowInfo, _ r: NSRect) {
        box(r, hex(0x1D1F21))
        box(NSRect(x: 0, y: 0, width: r.width, height: 30), hex(0x2B2D30))
        trafficLights(9)
        let active = w.tabs.first(where: \.active)
        text(active?.title ?? "zsh", NSPoint(x: r.width / 2 - 30, y: 7), size: 12, color: hex(0xB0B0B0))
        let dir = active?.detail?.components(separatedBy: " · ").first ?? "~"
        let script: [(String, UInt32)] = active?.title == "swift build"
            ? [("\(dir) ❯ swift build", 0xE0E0E0), ("Building for debugging...", 0x9AA0A6),
               ("[12/14] Compiling App ForecastView.swift", 0x9AA0A6), ("[14/14] Linking weather-app", 0x9AA0A6),
               ("Build complete! (4.21s)", 0x8BD49C), ("\(dir) ❯ ▌", 0xE0E0E0)]
            : [("\(dir) ❯ npm run dev", 0xE0E0E0), ("> blog@1.0.0 dev", 0x9AA0A6), ("> astro dev", 0x9AA0A6),
               ("  🚀  astro  ready in 312 ms", 0x8BD49C), ("  ┃ Local    http://localhost:4321/", 0x7FB2F0),
               ("  ┃ Network  use --host to expose", 0x9AA0A6), ("12:31:07 [200] /posts/spaces 4ms", 0x9AA0A6),
               ("12:31:09 [200] / 3ms", 0x9AA0A6)]
        for (i, l) in script.enumerated() {
            text(l.0, NSPoint(x: 14, y: 44 + CGFloat(i) * 20), size: 12.5, color: hex(l.1), mono: true)
        }
    }

    private static func editor(_ w: WindowInfo, _ r: NSRect, seed: Int) {
        let sublime = w.bundleID?.contains("sublime") == true
        box(r, hex(sublime ? 0x272822 : 0x1E1E24))
        let side: CGFloat = sublime ? 0 : 220
        box(NSRect(x: 0, y: 0, width: r.width, height: 34), hex(sublime ? 0x1E1F1C : 0x18181C))
        trafficLights(11)
        if side > 0 {
            box(NSRect(x: 0, y: 34, width: side, height: r.height), hex(0x18181C))
            let files = ["▾ weather-app", "  ▾ Sources/App", "     ForecastView.swift", "     WeatherAPI.swift",
                         "     Models.swift", "  ▸ Tests", "  Package.swift", "  README.md"]
            for (i, f) in files.enumerated() {
                text(f, NSPoint(x: 12, y: 50 + CGFloat(i) * 22), size: 12, color: hex(i == 2 ? 0xFFFFFF : 0x9DA1A8))
            }
        }
        var x = side + 8
        for t in w.tabs {
            let width = CGFloat(t.title.count) * 7.5 + 28
            if t.active { box(NSRect(x: x, y: 4, width: width, height: 30), hex(sublime ? 0x272822 : 0x1E1E24), radius: 4) }
            text(t.title, NSPoint(x: x + 14, y: 12), size: 12, color: hex(t.active ? 0xF0F0F0 : 0x8A8F98))
            x += width + 4
        }
        let palette: [UInt32] = [0xC678DD, 0x61AFEF, 0xE5C07B, 0x98C379, 0xABB2BF, 0xD19A66, 0x56B6C2]
        var i = seed
        var y: CGFloat = 50
        var indent: CGFloat = 0
        var n = 1
        while y < r.height - 16 {
            text("\(n)", NSPoint(x: side + 10, y: y - 3), size: 11, color: hex(0x5C6370), mono: true)
            i = (i &* 1103515245 &+ 12345) & 0x7fffffff
            if i % 9 != 0 {
                var cx = side + 50 + indent * 28
                for k in 0..<(1 + i % 4) {
                    let wdt = CGFloat(30 + (i >> (k * 3)) % 110)
                    if cx + wdt > r.width - 20 { break }
                    box(NSRect(x: cx, y: y, width: wdt, height: 9), hex(palette[(i >> k) % palette.count], 0.9), radius: 3)
                    cx += wdt + 8
                }
                indent = CGFloat((i >> 5) % 4)
            }
            y += 20
            n += 1
        }
    }

    private static func finder(_ w: WindowInfo, _ r: NSRect) {
        box(r, .white)
        box(NSRect(x: 0, y: 0, width: 180, height: r.height), hex(0xEDEDED))
        trafficLights(14)
        for (i, s) in ["Favorites", "  Desktop", "  Downloads", "  Documents", "  Applications", "iCloud", "  iCloud Drive"].enumerated() {
            text(s, NSPoint(x: 14, y: 46 + CGFloat(i) * 24), size: 12, color: hex(s.hasPrefix(" ") ? 0x333333 : 0x999999))
        }
        text(w.tabs.first(where: \.active)?.title ?? "Finder", NSPoint(x: 200, y: 12), size: 14, color: hex(0x222222), weight: .semibold)
        let names = ["invoice-oct.pdf", "IMG_2041.jpg", "IMG_2042.jpg", "trail-map.pdf", "slides.key", "notes.txt",
                     "setup.dmg", "podcast.mp3", "IMG_2050.heic", "budget.numbers", "archive.zip", "screenshot.png"]
        let colors: [UInt32] = [0xE8590C, 0x74C0FC, 0x74C0FC, 0xE8590C, 0x4DABF7, 0xADB5BD, 0x868E96, 0xDA77F2,
                                0x74C0FC, 0x51CF66, 0xADB5BD, 0x74C0FC]
        let cols = max(1, Int((r.width - 200) / 120))
        for (i, n) in names.enumerated() {
            let x = 200 + CGFloat(i % cols) * 120, y = 60 + CGFloat(i / cols) * 120
            if y + 100 > r.height { break }
            box(NSRect(x: x + 30, y: y, width: 56, height: 70), hex(colors[i], 0.85), radius: 6)
            text(n, NSPoint(x: x + 10, y: y + 78), size: 11, color: hex(0x333333))
        }
    }

    private static func document(_ w: WindowInfo, _ r: NSRect, seed: Int) {
        box(r, hex(0xE9E9EB))
        box(NSRect(x: 0, y: 0, width: r.width, height: 38), hex(0xF6F6F6))
        trafficLights(13)
        text(w.title, NSPoint(x: 90, y: 11), size: 13, color: hex(0x333333), weight: .medium)
        let page = NSRect(x: 60, y: 64, width: r.width - 120, height: r.height - 64)
        box(page, .white)
        text(w.title.replacingOccurrences(of: ".pdf", with: "").capitalized, NSPoint(x: page.minX + 40, y: page.minY + 36),
             size: 24, color: hex(0x222222), weight: .bold)
        box(NSRect(x: page.minX + 40, y: page.minY + 90, width: page.width - 80, height: 180), hex(0x8CE99A, 0.5), radius: 4)
        lines(in: NSRect(x: page.minX + 40, y: page.minY + 300, width: page.width - 80, height: page.height - 320),
              seed: seed, color: hex(0xCED4DA))
    }
}
