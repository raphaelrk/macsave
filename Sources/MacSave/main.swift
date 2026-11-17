import AppKit

let cliFlags: Set<String> = ["--print", "--json", "--save", "--help", "-h", "--markdown", "--summarize"]
let argv = Array(CommandLine.arguments.dropFirst())

if let i = argv.firstIndex(of: "--preview-test"), i + 1 < argv.count {
    // Debug: capture every window + each desktop composite into a folder.
    let dir = URL(fileURLWithPath: argv[i + 1])
    let snap = Collector.snapshot()
    var done = false
    Task.detached {
        for w in snap.windows {
            guard let wid = w.windowID, !w.minimized else { continue }
            let t0 = Date()
            let img = await Previews.window(wid)
            let where_ = w.spaceIDs.compactMap { snap.space($0).map { snap.label(for: $0) } }.joined(separator: ",")
            fputs(String(format: "%.1fs ", Date().timeIntervalSince(t0)) + "\(img == nil ? "FAIL" : "ok  ") \(w.app) [\(where_)] min=\(w.minimized) \(w.title.prefix(40))\n", stderr)
            if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("win-\(wid).png"))
            }
        }
        for sec in desktopSections(snap, snap.windows) {
            if let img = await Previews.desktop(sec.windows), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(sec.key).png"))
                fputs("desktop ok: \(sec.title)\n", stderr)
            }
        }
        done = true
    }
    while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
} else if let i = argv.firstIndex(of: "--close-window-id"), i + 1 < argv.count, let wid = UInt32(argv[i + 1]) {
    // Debug: close one window from the current snapshot by CGWindowID.
    if let w = Collector.snapshot().windows.first(where: { $0.windowID == wid }) {
        print(Closer.closeWindow(w) ?? "closed \(w.app) — \(w.title)")
    } else { print("window \(wid) not found") }
} else if let i = argv.firstIndex(of: "--screenshot"), i + 1 < argv.count {
    renderScreenshots(to: argv[i + 1], demo: argv.contains("--demo"))
} else if argv.contains(where: { cliFlags.contains($0) || $0.hasPrefix("--scope") }) {
    runCLI(argv)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

func runCLI(_ args: [String]) {
    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    if args.contains("--help") || args.contains("-h") {
        print("""
        MacSave — snapshot every app's windows/tabs, grouped by macOS desktop.
          --print                 print the text snapshot (default)
          --json                  print the raw snapshot as JSON
          --markdown              markdown output
          --scope all|current|minimized
          --one-line / --no-urls / --tabs-only
          --summarize claude|codex  prepend an AI summary
          --save [template]       save to file (default \(Saver.defaultTemplate))
          --demo                  use fake data (also works for the app: MacSave --demo)
        Run without flags to launch the menu bar app.
        """)
        return
    }
    let snap = args.contains("--demo") ? Demo.snapshot() : Collector.snapshot()
    if args.contains("--json") {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        print(String(decoding: try! enc.encode(snap), as: UTF8.self))
        return
    }
    var o = FormatOptions()
    o.markdown = args.contains("--markdown")
    o.oneLine = args.contains("--one-line")
    o.includeURLs = !args.contains("--no-urls")
    o.includeTabless = !args.contains("--tabs-only")
    let scope = value("--scope").flatMap(Scope.init(rawValue:)) ?? .all
    var summary: String?
    if let name = value("--summarize"), let p = AIProvider(rawValue: name) {
        guard let path = AI.locate(p) else { fputs("\(p.displayName) not found\n", stderr); exit(1) }
        switch AI.summarize(format(snap, scope: scope, options: o), with: p, path: path) {
        case .success(let s): summary = s
        case .failure(let e): fputs("\(e.localizedDescription)\n", stderr)
        }
    }
    let text = format(snap, scope: scope, options: o, summary: summary)
    if args.contains("--save") {
        let t = value("--save").flatMap { $0.hasPrefix("--") ? nil : $0 } ?? Saver.defaultTemplate
        do { print("Saved \(try Saver.save(text, snapshot: snap, template: t, json: false).path)") }
        catch { fputs("Save failed: \(error)\n", stderr); exit(1) }
    } else {
        print(text, terminator: "")
    }
}
