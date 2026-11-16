import AppKit
import SQLite3

struct ScriptWin {
    var name: String
    var bounds: Rect?
    var minimized: Bool?
    var tabs: [TabInfo]
    var note: String?
    var id: Int?
}

private func rect(_ any: Any?) -> Rect? {
    guard let d = any as? [String: Any],
          let x = (d["x"] as? NSNumber)?.doubleValue, let y = (d["y"] as? NSNumber)?.doubleValue,
          let w = (d["width"] as? NSNumber)?.doubleValue, let h = (d["height"] as? NSNumber)?.doubleValue
    else { return nil }
    return Rect(x: x, y: y, width: w, height: h)
}

private func anyInt(_ v: Any?) -> Int? {
    if let n = v as? NSNumber { return n.intValue }
    if let s = v as? String { return Int(s) }
    return nil
}

private func automationError(_ app: String, _ err: String) -> String {
    if err.contains("-1743") || err.localizedCaseInsensitiveContains("not allowed") || err.localizedCaseInsensitiveContains("not authorized") {
        return "\(app): Automation not allowed — enable it in System Settings › Privacy & Security › Automation"
    }
    return "\(app): couldn't read tabs (\(err.prefix(160)))"
}

enum AppKind {
    case chromium, safari, iterm, terminal, finder, sublime, vscode(URL)
}

private let chromiumIDs: Set<String> = [
    "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
    "com.brave.Browser", "com.microsoft.edgemac", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Beta",
    "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.operasoftware.Opera",
]

func appKind(_ app: NSRunningApplication) -> AppKind? {
    let id = app.bundleIdentifier ?? ""
    if chromiumIDs.contains(id) { return .chromium }
    if id == "com.apple.Safari" || id == "com.apple.SafariTechnologyPreview" { return .safari }
    if id == "com.googlecode.iterm2" { return .iterm }
    if id == "com.apple.Terminal" { return .terminal }
    if id == "com.apple.finder" { return .finder }
    if id.hasPrefix("com.sublimetext") { return .sublime }
    let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    for name in [app.localizedName, vscodeDirNames[id]].compactMap({ $0 }) {
        let dir = support.appendingPathComponent(name).appendingPathComponent("User/workspaceStorage")
        if FileManager.default.fileExists(atPath: dir.path) { return .vscode(dir) }
    }
    return nil
}

private let vscodeDirNames = [
    "com.microsoft.VSCode": "Code", "com.microsoft.VSCodeInsiders": "Code - Insiders",
    "com.todesktop.230313mzl4w4u92": "Cursor", "com.exafunction.windsurf": "Windsurf",
    "com.vscodium": "VSCodium",
]

/// Returns script-derived windows for an app, plus an optional warning.
func scriptWindows(kind: AppKind, app: NSRunningApplication, axTitles: [String]) -> ([ScriptWin], String?) {
    let id = app.bundleIdentifier ?? ""
    let name = app.localizedName ?? id
    switch kind {
    case .chromium, .safari:
        let (json, err) = runJXA(kind.isSafari ? JXA.safari : JXA.chromium, args: [id])
        guard let arr = json as? [[String: Any]] else { return ([], err.map { automationError(name, $0) }) }
        return (arr.map { o in
            let titles = o["titles"] as? [String] ?? [], urls = o["urls"] as? [Any] ?? []
            let activeIdx = (o["activeIndex"] as? Int).map { $0 - 1 }
            let activeTitle = o["activeTitle"] as? String
            let tabIDs = o["tabIDs"] as? [Any] ?? []
            let tabs = titles.enumerated().map { i, t in
                TabInfo(title: t, url: i < urls.count ? urls[i] as? String : nil,
                        active: activeIdx.map { $0 == i } ?? (t == activeTitle),
                        id: i < tabIDs.count ? anyInt(tabIDs[i]) : nil)
            }
            let incog = (o["mode"] as? String) == "incognito"
            return ScriptWin(name: o["name"] as? String ?? "", bounds: rect(o["bounds"]),
                             minimized: o["minimized"] as? Bool, tabs: tabs, note: incog ? "Incognito" : nil,
                             id: anyInt(o["id"]))
        }, nil)

    case .iterm, .terminal:
        let isIterm = { if case .iterm = kind { return true }; return false }()
        let (json, err) = runJXA(isIterm ? JXA.iterm : JXA.terminal, args: [id])
        guard let arr = json as? [[String: Any]] else { return ([], err.map { automationError(name, $0) }) }
        let ttys = arr.flatMap { ($0["tabs"] as? [[String: Any]] ?? []).compactMap { $0["tty"] as? String } }
        let info = ttyInfo(ttys)
        return (arr.map { o in
            let tabs = (o["tabs"] as? [[String: Any]] ?? []).map { t -> TabInfo in
                let tty = t["tty"] as? String
                let ti = tty.flatMap { info[$0] }
                let path = (t["path"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? ti?.cwd
                var detail = [path.map(abbreviateHome), ti?.command].compactMap { $0 }.joined(separator: " · ")
                if let panes = t["panes"] as? Int, panes > 1 { detail += " (\(panes) panes)" }
                let title = (t["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? ti?.command ?? tty ?? "shell"
                return TabInfo(title: title, detail: detail.isEmpty ? nil : detail, active: t["active"] as? Bool ?? false)
            }
            return ScriptWin(name: o["name"] as? String ?? "", bounds: rect(o["bounds"]),
                             minimized: o["minimized"] as? Bool, tabs: tabs)
        }, nil)

    case .finder:
        let (json, err) = runJXA(JXA.finder, args: [id])
        guard let arr = json as? [[String: Any]] else { return ([], err.map { automationError(name, $0) }) }
        // Finder reports each tab as its own "window"; tabs of one window share bounds.
        var groups: [ScriptWin] = []
        for o in arr {
            let b = rect(o["bounds"])
            let path = (o["url"] as? String).flatMap { URL(string: $0)?.path }
            let tab = TabInfo(title: o["name"] as? String ?? "", detail: path.map(abbreviateHome))
            if let b, let i = groups.firstIndex(where: { $0.bounds.map { $0.close(to: b, tolerance: 1) } ?? false }) {
                groups[i].tabs.append(tab)
            } else {
                var first = tab; first.active = true
                groups.append(ScriptWin(name: tab.title, bounds: b, minimized: o["minimized"] as? Bool, tabs: [first]))
            }
        }
        return (groups, nil)

    case .sublime:
        return (sublimeWindows(), nil)

    case .vscode(let dir):
        return (vscodeWindows(storage: dir, titles: axTitles), nil)
    }
}

extension AppKind {
    var isSafari: Bool { if case .safari = self { return true }; return false }
    var hasStaleState: Bool {
        switch self { case .sublime, .vscode: return true; default: return false }
    }
}

// MARK: Terminal TTY → cwd / foreground command

struct TTYInfo { var cwd: String?; var command: String? }

private let shells: Set<String> = ["zsh", "-zsh", "bash", "-bash", "fish", "-fish", "sh", "login", "nu", "xonsh"]

func ttyInfo(_ ttys: [String]) -> [String: TTYInfo] {
    guard !ttys.isEmpty else { return [:] }
    let ps = runProcess("/bin/ps", ["-axo", "pid=,tty=,stat=,comm="], timeout: 5).out
    struct P { var pid: Int; var stat: String; var comm: String }
    var byTTY: [String: [P]] = [:]
    for line in ps.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4, let pid = Int(parts[0]) else { continue }
        byTTY["/dev/" + parts[1], default: []].append(
            P(pid: pid, stat: String(parts[2]),
              comm: (parts[3].trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent))
    }
    var chosen: [String: P] = [:]
    for tty in ttys {
        let procs = (byTTY[tty] ?? []).sorted { $0.pid < $1.pid }
        let fg = procs.filter { $0.stat.contains("+") }
        if let p = fg.first(where: { !shells.contains($0.comm) }) ?? fg.first ?? procs.first { chosen[tty] = p }
    }
    let pids = chosen.values.map { String($0.pid) }
    var cwd: [Int: String] = [:]
    if !pids.isEmpty {
        let out = runProcess("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", pids.joined(separator: ","), "-Fpn"], timeout: 8).out
        var cur: Int?
        for line in out.split(separator: "\n") {
            if line.hasPrefix("p") { cur = Int(line.dropFirst()) }
            else if line.hasPrefix("n"), let c = cur { cwd[c] = String(line.dropFirst()) }
        }
    }
    return chosen.mapValues { p in
        TTYInfo(cwd: cwd[p.pid], command: shells.contains(p.comm) ? nil : p.comm)
    }
}

// MARK: Sublime Text (session file)

private func sublimeWindows() -> [ScriptWin] {
    let fm = FileManager.default
    let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let candidates = ["Sublime Text", "Sublime Text 3"].flatMap { dir in
        ["Auto Save Session.sublime_session", "Session.sublime_session"].map {
            base.appendingPathComponent(dir).appendingPathComponent("Local").appendingPathComponent($0)
        }
    }
    let newest = candidates.compactMap { url -> (URL, Date)? in
        guard let d = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
        return (url, d)
    }.max { $0.1 < $1.1 }
    guard let (url, mtime) = newest, let data = try? Data(contentsOf: url),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let windows = root["windows"] as? [[String: Any]] else { return [] }
    let saved = DateFormatter.localizedString(from: mtime, dateStyle: .none, timeStyle: .short)
    return windows.map { w in
        let buffers = w["buffers"] as? [[String: Any]] ?? []
        let selectedGroup = w["selected_group"] as? Int ?? 0
        var tabs: [TabInfo] = []
        for (gi, g) in (w["groups"] as? [[String: Any]] ?? []).enumerated() {
            for s in g["sheets"] as? [[String: Any]] ?? [] {
                let bi = s["buffer"] as? Int
                let buf = bi.flatMap { $0 < buffers.count ? buffers[$0] : nil } ?? [:]
                let file = (s["file"] as? String) ?? (buf["file"] as? String)
                var title = file.map { ($0 as NSString).lastPathComponent } ?? ""
                if title.isEmpty, let n = (buf["settings"] as? [String: Any])?["name"] as? String { title = n }
                if title.isEmpty, let c = buf["contents"] as? String {
                    title = String(c.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    if title.count > 70 { title = String(title.prefix(70)) + "…" }
                }
                if title.isEmpty { title = "untitled" }
                let selected = (s["selected"] as? Bool ?? false) && gi == selectedGroup
                tabs.append(TabInfo(title: title, detail: file.map(abbreviateHome) ?? "(unsaved)", active: selected))
            }
        }
        let project = (w["project"] as? String).flatMap { $0.isEmpty ? nil : abbreviateHome($0) }
        let active = tabs.first { $0.active }?.title ?? tabs.first?.title ?? ""
        let note = [project, "from session saved \(saved)"].compactMap { $0 }.joined(separator: " · ")
        return ScriptWin(name: active, bounds: nil, minimized: nil, tabs: tabs, note: note)
    }
}

// MARK: VS Code family (Cursor, Code, Windsurf…) — per-workspace editor state

private struct VSWorkspace { var name: String; var root: String; var db: URL; var mtime: Date }

private func vscodeWorkspaces(_ storage: URL) -> [VSWorkspace] {
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil) else { return [] }
    return dirs.compactMap { dir in
        let db = dir.appendingPathComponent("state.vscdb")
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("workspace.json")),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uriStr = (j["folder"] as? String) ?? (j["workspace"] as? String),
              let uri = URL(string: uriStr),
              let mtime = (try? fm.attributesOfItem(atPath: db.path))?[.modificationDate] as? Date
        else { return nil }
        var name = uri.lastPathComponent
        var root = uri.path
        if name.hasSuffix(".code-workspace") {
            name = String(name.dropLast(".code-workspace".count))
            root = (root as NSString).deletingLastPathComponent
        }
        let display = uri.isFileURL ? root : uriStr
        return VSWorkspace(name: name, root: display, db: db, mtime: mtime)
    }
}

private func vscodeWindows(storage: URL, titles: [String]) -> [ScriptWin] {
    let workspaces = vscodeWorkspaces(storage)
    var out: [ScriptWin] = []
    var used = Set<URL>()
    for title in titles {
        let segments = title
            .components(separatedBy: " — ").flatMap { $0.components(separatedBy: " - ") }
            .map { $0.replacingOccurrences(of: " (Workspace)", with: "").trimmingCharacters(in: .whitespaces) }
        guard let ws = segments.lazy.compactMap({ seg in
            workspaces.filter { $0.name == seg && !used.contains($0.db) }.max { $0.mtime < $1.mtime }
        }).first else { continue }
        used.insert(ws.db)
        let saved = DateFormatter.localizedString(from: ws.mtime, dateStyle: .none, timeStyle: .short)
        out.append(ScriptWin(name: title, bounds: nil, minimized: nil, tabs: vscodeEditors(ws),
                             note: "\(abbreviateHome(ws.root)) · editor state saved \(saved)"))
    }
    return out
}

private func sqliteValue(_ db: URL, key: String) -> String? {
    var handle: OpaquePointer?
    guard sqlite3_open_v2(db.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_close(handle) }
    sqlite3_busy_timeout(handle, 500)
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "SELECT value FROM ItemTable WHERE key = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(stmt) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(stmt, 1, key, -1, transient)
    guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
    return String(cString: c)
}

private func vscodeEditors(_ ws: VSWorkspace) -> [TabInfo] {
    guard let raw = sqliteValue(ws.db, key: "memento/workbench.parts.editor"),
          let j = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
          let state = j["editorpart.state"] as? [String: Any],
          let grid = state["serializedGrid"] as? [String: Any],
          let root = grid["root"] as? [String: Any] else { return [] }
    let activeGroup = state["activeGroup"] as? Int
    var leaves: [[String: Any]] = []
    func walk(_ node: [String: Any]) {
        if node["type"] as? String == "leaf", let d = node["data"] as? [String: Any] { leaves.append(d) }
        for child in node["data"] as? [[String: Any]] ?? [] { walk(child) }
    }
    walk(root)
    var tabs: [TabInfo] = []
    for (gi, leaf) in leaves.enumerated() {
        let editors = leaf["editors"] as? [[String: Any]] ?? []
        let mruFirst = (leaf["mru"] as? [Int])?.first
        for (ei, e) in editors.enumerated() {
            var tab = describeEditor(e, root: ws.root)
            tab.active = ei == mruFirst && (leaf["id"] as? Int == activeGroup || leaves.count == 1)
            if leaves.count > 1 { tab.detail = (tab.detail.map { $0 + " · " } ?? "") + "split \(gi + 1)" }
            tabs.append(tab)
        }
    }
    return tabs
}

private func describeEditor(_ e: [String: Any], root: String) -> TabInfo {
    let id = e["id"] as? String ?? "editor"
    let value = (e["value"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
    func findPath(_ any: Any?) -> String? {
        if let d = any as? [String: Any] {
            if let p = d["fsPath"] as? String { return p }
            if let s = d["scheme"] as? String, s != "file", let ext = d["external"] as? String { return ext }
            if let r = d["resource"] as? String, let u = URL(string: r) { return u.isFileURL ? u.path : r }
            for k in ["resourceJSON", "resource", "modifiedInput", "primary", "original"] {
                if let p = findPath(d[k]) { return p }
            }
        }
        return nil
    }
    if let v = value as? [String: Any], let t = v["title"] as? String, !t.isEmpty {
        return TabInfo(title: t, detail: (v["viewType"] as? String).map { "(\($0))" })
    }
    guard let path = findPath(value) else {
        let short = id.split(separator: ".").last.map(String.init) ?? id
        return TabInfo(title: short.replacingOccurrences(of: "Input", with: ""))
    }
    let title = path.hasPrefix("/") ? (path as NSString).lastPathComponent : path
    var detail: String
    if path.hasPrefix(root + "/") { detail = String(path.dropFirst(root.count + 1)) }
    else { detail = abbreviateHome(path) }
    if id.contains("diff") || id.contains("Diff") { detail += " (diff)" }
    return TabInfo(title: title, detail: detail == title ? nil : detail)
}
