import AppKit

enum Closer {
    private static func kind(_ w: WindowInfo) -> AppKind? {
        NSRunningApplication(processIdentifier: w.pid).flatMap(appKind)
    }

    static func canCloseTabs(_ w: WindowInfo) -> Bool {
        guard w.scriptID != nil, let k = kind(w) else { return false }
        if case .chromium = k { return true }
        return k.isSafari
    }

    static func canClose(_ w: WindowInfo) -> Bool { w.windowID != nil || w.scriptID != nil }

    /// Returns nil on success, or an error message.
    static func closeWindow(_ w: WindowInfo) -> String? {
        if let sid = w.scriptID, let bid = w.bundleID {
            let (_, err) = runJXA(#"function run(a){ Application(a[0]).windows.byId(Number(a[1])).close(); return "1"; }"#,
                                  args: [bid, String(sid)])
            if err == nil { return nil }
        }
        if let wid = w.windowID, axCloseWindow(pid: w.pid, wid: wid) { return nil }
        return "Couldn't close \(w.app) window"
    }

    static func closeTab(_ t: TabInfo, in w: WindowInfo) -> String? {
        guard let sid = w.scriptID, let bid = w.bundleID, let k = kind(w) else { return "Can't close this tab" }
        let err: String?
        if k.isSafari {
            (_, err) = runJXA(#"""
            function run(a){ const w = Application(a[0]).windows.byId(Number(a[1]));
              const i = w.tabs.url().indexOf(a[2]); if (i < 0) throw new Error("tab not found");
              w.tabs[i].close(); return "1"; }
            """#, args: [bid, String(sid), t.url ?? ""])
        } else {
            guard let tid = t.id else { return "Can't close this tab" }
            (_, err) = runJXA(#"function run(a){ Application(a[0]).windows.byId(Number(a[1])).tabs.byId(Number(a[2])).close(); return "1"; }"#,
                              args: [bid, String(sid), String(tid)])
        }
        return err.map { "Couldn't close tab: \($0.prefix(120))" }
    }
}

extension WindowInfo {
    func same(_ o: WindowInfo) -> Bool {
        pid == o.pid && windowID == o.windowID && scriptID == o.scriptID && title == o.title
    }
}

extension TabInfo {
    func same(_ o: TabInfo) -> Bool {
        if let id, let oid = o.id { return id == oid }
        return title == o.title && url == o.url && detail == o.detail
    }
}
