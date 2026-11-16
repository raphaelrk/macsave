import AppKit
import ScreenCaptureKit

/// Live window images via ScreenCaptureKit (needs Screen Recording permission).
/// Background browser tabs have no rendered image, so only windows/desktops get previews.
enum Previews {
    private static var cache: [CGWindowID: (Date, NSImage)] = [:]
    private static let lock = NSLock()

    private static func cached(_ wid: CGWindowID) -> NSImage? {
        lock.withLock { cache[wid].flatMap { Date().timeIntervalSince($0.0) < 20 ? $0.1 : nil } }
    }
    private static func store(_ wid: CGWindowID, _ img: NSImage) { lock.withLock { cache[wid] = (Date(), img) } }

    @available(macOS 14.0, *)
    private static func scWindows() async throws -> [CGWindowID: SCWindow] {
        if let (d, m) = lock.withLock({ windowList }), Date().timeIntervalSince(d) < 5,
           let m = m as? [CGWindowID: SCWindow] { return m }
        guard let content = await withTimeout(4, {
            try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }) else { return [:] }
        let m = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
        lock.withLock { windowList = (Date(), m) }
        return m
    }
    private static var windowList: (Date, Any)?

    static func window(_ wid: CGWindowID, maxSize: CGFloat = 1400) async -> NSImage? {
        if let img = cached(wid) { return img }
        guard #available(macOS 14.0, *) else { return nil }
        do {
            guard let w = try await scWindows()[wid] else { return nil }
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let config = SCStreamConfiguration()
            let scale = min(1, maxSize / max(w.frame.width, w.frame.height)) * CGFloat(filter.pointPixelScale)
            config.width = max(1, Int(w.frame.width * scale))
            config.height = max(1, Int(w.frame.height * scale))
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            guard let cg = await withTimeout(3, {
                try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            }) else { return nil }
            let img = NSImage(cgImage: cg, size: w.frame.size)
            store(wid, img)
            return img
        } catch {
            return nil
        }
    }

    /// Composites a desktop from its windows' captures, back to front, at their on-screen positions.
    static func desktop(_ windows: [WindowInfo], maxWidth: CGFloat = 1400) async -> NSImage? {
        let visible = windows.filter { !$0.minimized && !$0.appHidden && $0.windowID != nil && $0.bounds != nil }
            .sorted { $0.zOrder > $1.zOrder }
        guard !visible.isEmpty else { return nil }
        let screens = NSScreen.screens.map(\.frame)
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        // Canvas = the screen (in top-left coords) containing the most windows' origins.
        let topLeftScreens = screens.map { CGRect(x: $0.minX, y: mainH - $0.maxY, width: $0.width, height: $0.height) }
        let canvas = topLeftScreens.max { a, b in
            visible.filter { a.contains(CGPoint(x: $0.bounds!.x + 5, y: $0.bounds!.y + 5)) }.count <
            visible.filter { b.contains(CGPoint(x: $0.bounds!.x + 5, y: $0.bounds!.y + 5)) }.count
        } ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var images: [(WindowInfo, NSImage)] = []
        for w in visible {
            if let img = await window(w.windowID!, maxSize: 900) { images.append((w, img)) }
        }
        guard !images.isEmpty else { return nil }
        let scale = min(1, maxWidth / canvas.width)
        let size = NSSize(width: canvas.width * scale, height: canvas.height * scale)
        let out = NSImage(size: size)
        out.lockFocus()
        NSColor(white: 0.18, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        for (w, img) in images {
            let b = w.bounds!
            let r = NSRect(x: (b.x - canvas.minX) * scale,
                           y: size.height - (b.y - canvas.minY + b.height) * scale,
                           width: b.width * scale, height: b.height * scale)
            img.draw(in: r)
        }
        out.unlockFocus()
        return out
    }
}

/// Returns nil if `op` hasn't finished in time; a stuck operation is abandoned rather than awaited.
private final class Once: @unchecked Sendable {
    let lock = NSLock()
    var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async -> T? {
    let once = Once()
    return await withCheckedContinuation { (cont: CheckedContinuation<T?, Never>) in
        Task {
            let r = try? await op()
            if once.claim() { cont.resume(returning: r) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if once.claim() { cont.resume(returning: nil) }
        }
    }
}
