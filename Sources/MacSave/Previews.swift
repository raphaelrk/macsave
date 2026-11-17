import AppKit
import ScreenCaptureKit

/// Live window images via ScreenCaptureKit (needs Screen Recording permission).
/// Background browser tabs have no rendered image, so only windows/desktops get previews.
enum Previews {
    /// Set in demo mode: synthetic images instead of real captures.
    static var demo: [CGWindowID: NSImage]?
    private static var cache: [CGWindowID: (Date, NSImage)] = [:]
    private static var inflight: [CGWindowID: Task<NSImage?, Never>] = [:]
    private static var windowList: (Date, Task<[CGWindowID: SCWindow], Never>)?
    private static let lock = NSLock()

    private static func scWindows() async -> [CGWindowID: SCWindow] {
        let task = lock.withLock { () -> Task<[CGWindowID: SCWindow], Never> in
            if let (d, t) = windowList, Date().timeIntervalSince(d) < 5 { return t }
            let t = Task {
                guard let content = await withTimeout(4, {
                    try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                }) else { return [CGWindowID: SCWindow]() }
                return Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            }
            windowList = (Date(), t)
            return t
        }
        return await task.value
    }

    /// Cached for 20s; concurrent requests for the same window share one capture.
    static func window(_ wid: CGWindowID) async -> NSImage? {
        if let demo { return demo[wid] }
        let task = lock.withLock { () -> Task<NSImage?, Never> in
            if let (d, img) = cache[wid], Date().timeIntervalSince(d) < 20 { return Task { img } }
            if let t = inflight[wid] { return t }
            let t = Task { await capture(wid) }
            inflight[wid] = t
            return t
        }
        let img = await task.value
        lock.withLock {
            inflight[wid] = nil
            if let img { cache[wid] = (Date(), img) }
        }
        return img
    }

    private static func capture(_ wid: CGWindowID, maxSize: CGFloat = 1400) async -> NSImage? {
        guard #available(macOS 14.0, *), let w = await scWindows()[wid] else { return nil }
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
        return NSImage(cgImage: cg, size: w.frame.size)
    }

    /// Composites a desktop from its windows' captures, back to front, at their on-screen positions.
    static func desktop(_ windows: [WindowInfo], maxWidth: CGFloat = 1400) async -> NSImage? {
        let visible = windows.filter { !$0.minimized && !$0.appHidden && $0.windowID != nil && $0.bounds != nil }
            .sorted { $0.zOrder > $1.zOrder }
        guard !visible.isEmpty else { return nil }
        let screens = demo != nil ? [Demo.canvas] : NSScreen.screens.map(\.frame)
        let mainH = demo != nil ? Demo.canvas.height : NSScreen.screens.first?.frame.height ?? 0
        // Canvas = the screen (in top-left coords) containing the most windows' origins.
        let topLeftScreens = screens.map { CGRect(x: $0.minX, y: mainH - $0.maxY, width: $0.width, height: $0.height) }
        let canvas = topLeftScreens.max { a, b in
            visible.filter { a.contains(CGPoint(x: $0.bounds!.x + 5, y: $0.bounds!.y + 5)) }.count <
            visible.filter { b.contains(CGPoint(x: $0.bounds!.x + 5, y: $0.bounds!.y + 5)) }.count
        } ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var images: [(WindowInfo, NSImage)] = []
        for w in visible {
            if let img = await window(w.windowID!) { images.append((w, img)) }
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
