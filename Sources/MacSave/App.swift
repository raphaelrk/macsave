import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = Model()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    init() {
        DispatchQueue.global().async {
            let found = AI.available()
            DispatchQueue.main.async { self.ai = found }
        }
    }

    func refresh() {
        guard !loading else { return }
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
        DispatchQueue.global(qos: .userInitiated).async {
            let err = tab.map { Closer.closeTab($0, in: w) } ?? Closer.closeWindow(w)
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
func renderScreenshots(to dir: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let model = Model()
    model.snapshot = Collector.snapshot()
    model.status = "Captured (screenshot mode)"
    for mode in Mode.allCases {
        UserDefaults.standard.set(mode.rawValue, forKey: "mode")
        let view = NSHostingView(rootView: MainView(model: model))
        view.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = view
        view.frame = window.contentLayoutRect
        view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("macsave-\(mode.rawValue).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        print("Wrote \(url.path)")
    }
}
