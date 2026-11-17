import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = Model(demo: CommandLine.arguments.contains("--demo"))

    static let showNotification = Notification.Name("com.raphaelrk.macsave.show")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: another copy (e.g. build/ vs ~/Applications) hands off to the running one.
        let me = NSRunningApplication.current
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != me && !$0.isTerminated }) {
            DistributedNotificationCenter.default().postNotificationName(Self.showNotification, object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: Self.showNotification, object: nil, queue: .main) { [weak self] _ in
            self?.show()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "MacSave")
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.target = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 900, height: 640)
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = NSHostingController(rootView: MainView(model: model))
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        DispatchQueue.main.async { self.toggle() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    func show() { if !popover.isShown { toggle() } }

    @objc func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

final class Model: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var loading = false
    @Published var summary: String?
    @Published var summarizing: AIProvider?
    @Published var status = ""
    @Published var lastSaved: URL?
    @Published var ai: [AIProvider: String] = [:]
    /// Demo mode shows fake data and never touches real windows.
    let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        DispatchQueue.global().async {
            let found = AI.available()
            DispatchQueue.main.async { self.ai = found }
        }
    }

    func refresh() {
        guard !loading else { return }
        if demo {
            let s = Demo.snapshot()
            Previews.demo = Demo.images(s)
            snapshot = s
            status = "Demo data"
            return
        }
        loading = true
        status = "Scanning windows…"
        DispatchQueue.global(qos: .userInitiated).async {
            let start = Date()
            let s = Collector.snapshot()
            DispatchQueue.main.async {
                self.snapshot = s
                self.summary = nil
                self.loading = false
                self.status = String(format: "Captured %@ in %.1fs", headerDate(s.date), Date().timeIntervalSince(start))
            }
        }
    }

    func close(_ w: WindowInfo, tab: TabInfo? = nil) {
        let demo = self.demo
        DispatchQueue.global(qos: .userInitiated).async {
            let err = demo ? nil : tab.map { Closer.closeTab($0, in: w) } ?? Closer.closeWindow(w)
            DispatchQueue.main.async {
                if let err { self.status = err; return }
                guard var s = self.snapshot, let wi = s.windows.firstIndex(where: { $0.same(w) }) else { return }
                if let tab {
                    s.windows[wi].tabs.removeAll { $0.same(tab) }
                    self.status = "Closed tab “\(tab.title.prefix(60))”"
                } else {
                    s.windows.remove(at: wi)
                    self.status = "Closed \(w.app) window"
                }
                self.snapshot = s
            }
        }
    }

    var closableMinimized: [WindowInfo] {
        snapshot?.windows.filter { $0.minimized && Closer.canClose($0) } ?? []
    }

    func closeMinimized() {
        let targets = closableMinimized
        guard !targets.isEmpty else { return }
        status = "Closing \(targets.count) minimized windows…"
        let demo = self.demo
        DispatchQueue.global(qos: .userInitiated).async {
            var closed: [WindowInfo] = []
            for w in targets where demo || Closer.closeWindow(w) == nil { closed.append(w) }
            DispatchQueue.main.async {
                if var s = self.snapshot {
                    s.windows.removeAll { w in closed.contains { $0.same(w) } }
                    self.snapshot = s
                }
                let failed = targets.count - closed.count
                self.status = "Closed \(closed.count) minimized window\(closed.count == 1 ? "" : "s")"
                    + (failed > 0 ? " · \(failed) couldn't be closed" : "")
            }
        }
    }

    func summarize(_ text: String, with p: AIProvider) {
        guard let path = ai[p], summarizing == nil else { return }
        summarizing = p
        status = "Asking \(p.displayName)…"
        DispatchQueue.global().async {
            let r = AI.summarize(text, with: p, path: path)
            DispatchQueue.main.async {
                self.summarizing = nil
                switch r {
                case .success(let s): self.summary = s; self.status = "Summary added by \(p.displayName)"
                case .failure(let e): self.status = e.localizedDescription
                }
            }
        }
    }
}


/// Debug: render each mode of the popover offscreen to PNGs (`MacSave --screenshot <dir>`).
func renderScreenshots(to dir: String, demo: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let model = Model(demo: demo)
    if demo { model.refresh() } else { model.snapshot = Collector.snapshot() }
    model.status = demo ? "Captured Nov 16 2026 12:33 PM Mon in 0.9s" : "Captured (screenshot mode)"
    let saved = UserDefaults.standard.string(forKey: "mode")
    defer { UserDefaults.standard.set(saved, forKey: "mode") }
    for mode in Mode.allCases {
        UserDefaults.standard.set(mode.rawValue, forKey: "mode")
        let view = NSHostingView(rootView: MainView(model: model))
        view.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.frame = window.contentLayoutRect
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("macsave-\(mode.rawValue).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("Wrote \(url.path)")
    }
}
