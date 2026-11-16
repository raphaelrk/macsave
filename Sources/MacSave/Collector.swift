import AppKit

enum Collector {
    static let debug = ProcessInfo.processInfo.environment["MACSAVE_DEBUG"] != nil

    static func snapshot() -> Snapshot {
        var warnings: [String] = []
        let trusted = AXIsProcessTrusted()
        if !trusted {
            warnings.append("Accessibility not granted — window titles, minimized state and non-browser windows are limited (System Settings › Privacy & Security › Accessibility)")
        }
        let (spaces, displayCount) = readSpaces()
        let cg = readCGWindows()
        let cgByID = Dictionary(cg.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let me = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me
        }
        let focused = trusted ? focusedWindowID() : nil
        let lock = NSLock()
        var windows: [WindowInfo] = []

        DispatchQueue.concurrentPerform(iterations: apps.count) { i in
            let app = apps[i]
            let pid = app.processIdentifier
            let name = app.localizedName ?? app.bundleIdentifier ?? "pid \(pid)"
            let candidates = cg.filter { $0.pid == pid && $0.layer == 0 && $0.bounds.width >= 80 && $0.bounds.height >= 60 }
            var appWindows: [WindowInfo] = []

            func base(_ id: CGWindowID?, title: String, bounds: Rect?, minimized: Bool) -> WindowInfo {
                var w = WindowInfo(windowID: id, app: name, bundleID: app.bundleIdentifier, pid: pid, title: title,
                                   bounds: bounds, minimized: minimized, appHidden: app.isHidden)
                if let id {
                    w.spaceIDs = spacesForWindow(id)
                    w.zOrder = cgByID[id]?.z ?? .max
                    w.focused = id == focused
                }
                return w
            }

            let tAX = Date()
            defer { if debug { fputs(String(format: "[macsave] %@ windows: %.2fs\n", name, tAX.timeIntervalSinceNow * -1), stderr) } }
            if trusted {
                for a in axWindows(for: app, cgCandidates: Set(candidates.map(\.id))) {
                    var w = base(a.id, title: a.title, bounds: a.bounds ?? a.id.flatMap { cgByID[$0]?.bounds }, minimized: a.minimized)
                    w.tabs = nativeTabs(a.element)
                    appWindows.append(w)
                }
            }
            // CG fallback: windows AX couldn't reach (or no AX permission). Untitled ones are kept only
            // if a scripted app (browser/terminal) later attaches tabs to them.
            let covered = Set(appWindows.compactMap(\.windowID))
            for c in candidates where !covered.contains(c.id) && (trusted ? true : (c.onscreen || !(c.name ?? "").isEmpty)) {
                appWindows.append(base(c.id, title: c.name ?? "", bounds: c.bounds, minimized: false))
            }

            var warning: String?
            let t0 = Date()
            defer { if debug { fputs(String(format: "[macsave] %@: %.2fs\n", name, Date().timeIntervalSince(t0)), stderr) } }
            if let kind = appKind(app) {
                let (scripted, err) = scriptWindows(kind: kind, app: app, axTitles: appWindows.map(\.title))
                warning = err
                merge(scripted, into: &appWindows, appName: name, app: app, kind: kind)
            }

            appWindows.removeAll {
                $0.title.isEmpty && $0.tabs.isEmpty && ($0.spaceIDs.isEmpty || $0.windowID.map { !covered.contains($0) } ?? false)
            }
            lock.lock()
            windows += appWindows
            if let warning { warnings.append(warning) }
            lock.unlock()
        }

        windows.sort { ($0.zOrder, $0.app, $0.title) < ($1.zOrder, $1.app, $1.title) }
        return Snapshot(date: Date(), displayCount: displayCount, spaces: spaces, windows: windows,
                        warnings: warnings.sorted())
    }

    /// Pairs script-derived windows (which have tabs but no desktop info) with AX/CG windows.
    private static func merge(_ scripted: [ScriptWin], into windows: inout [WindowInfo], appName: String,
                              app: NSRunningApplication, kind: AppKind) {
        var pairs: [(score: Int, s: Int, w: Int)] = []
        for (si, s) in scripted.enumerated() {
            for (wi, w) in windows.enumerated() {
                var score = 0
                if let a = s.bounds, let b = w.bounds, a.close(to: b) { score += 10 }
                let t = w.title, n = s.name
                if !n.isEmpty && !t.isEmpty {
                    if t == n { score += 6 } else if t.contains(n) || n.contains(t) { score += 4 }
                }
                if let m = s.minimized, m == w.minimized { score += 1 }
                if score >= 4 { pairs.append((score, si, wi)) }
            }
        }
        var usedS = Set<Int>(), usedW = Set<Int>()
        for p in pairs.sorted(by: { $0.score > $1.score }) where !usedS.contains(p.s) && !usedW.contains(p.w) {
            apply(scripted[p.s], to: &windows[p.w])
            usedS.insert(p.s); usedW.insert(p.w)
        }
        let leftS = scripted.indices.filter { !usedS.contains($0) }
        let leftW = windows.indices.filter { !usedW.contains($0) }
        if leftS.count == 1 && leftW.count == 1 {
            apply(scripted[leftS[0]], to: &windows[leftW[0]])
            return
        }
        for si in leftS where !kind.hasStaleState {
            let s = scripted[si]
            var w = WindowInfo(windowID: nil, app: appName, bundleID: app.bundleIdentifier, pid: app.processIdentifier,
                               title: s.name, bounds: s.bounds, minimized: s.minimized ?? false, appHidden: app.isHidden)
            w.tabs = s.tabs
            w.scriptID = s.id
            w.note = [s.note, "desktop unknown"].compactMap { $0 }.joined(separator: " · ")
            windows.append(w)
        }
    }

    private static func apply(_ s: ScriptWin, to w: inout WindowInfo) {
        w.tabs = s.tabs
        w.scriptID = s.id
        if let n = s.note { w.note = n }
        if let m = s.minimized, m { w.minimized = true }
        if w.title.isEmpty { w.title = s.name }
    }
}
