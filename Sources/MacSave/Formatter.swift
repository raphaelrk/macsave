import Foundation

enum Scope: String, CaseIterable, Identifiable {
    case all, current, minimized
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "all desktops"
        case .current: return "current desktop"
        case .minimized: return "minimized & hidden"
        }
    }
}

struct FormatOptions {
    var includeURLs = true
    var oneLine = false
    var markdown = false
    var includeTabless = true
}

private func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

func headerDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "MMM d yyyy h:mm a EEE"
    return f.string(from: d)
}

func filtered(_ s: Snapshot, _ scope: Scope, _ o: FormatOptions) -> [WindowInfo] {
    let current = Set(s.spaces.filter(\.current).map(\.id))
    return s.windows.filter { w in
        if !o.includeTabless && w.tabs.isEmpty { return false }
        switch scope {
        case .all: return true
        case .current: return !w.minimized && !w.appHidden && !current.isDisjoint(with: w.spaceIDs)
        case .minimized: return w.minimized || w.appHidden
        }
    }
}

enum LineRole { case summary, title, meta, warning, section, window, tab, link, blank }

struct StyledLine {
    var text: String
    var role: LineRole
    var focused = false
    var dim = false
    var active = false
    var url: String?
    var isPath = false
}

func format(_ s: Snapshot, scope: Scope, options o: FormatOptions, summary: String? = nil) -> String {
    styledLines(s, scope: scope, options: o, summary: summary).map(\.text).joined(separator: "\n") + "\n"
}

func styledLines(_ s: Snapshot, scope: Scope, options o: FormatOptions, summary: String? = nil) -> [StyledLine] {
    let windows = filtered(s, scope, o)
    var lines: [StyledLine] = []
    func add(_ t: String, _ r: LineRole) { lines.append(StyledLine(text: t, role: r)) }
    let blank = StyledLine(text: "", role: .blank)
    let h1 = o.markdown ? "# " : ""
    let h2 = o.markdown ? "## " : ""

    if let summary, !summary.isEmpty {
        for l in summary.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n") { add(l, .summary) }
        lines += [blank]
        add(o.markdown ? "---" : "————————", .meta)
        lines += [blank]
    }

    let userDesktops = s.spaces.filter { !$0.fullscreen }.count
    let fullscreens = s.spaces.count - userDesktops
    let tabs = windows.reduce(0) { $0 + $1.tabs.count }
    add("\(h1)Mac Bankruptcy \(headerDate(s.date)) (\(scope.label))", .title)
    var counts = [plural(userDesktops, "desktop")]
    if fullscreens > 0 { counts.append("\(fullscreens) fullscreen") }
    if s.displayCount > 1 { counts.append(plural(s.displayCount, "display")) }
    let mins = windows.filter(\.minimized).count, hidden = windows.filter(\.appHidden).count
    add(counts.joined(separator: ", ")
        + ", \(plural(windows.count, "window")) (\(mins) minimized, \(hidden) in hidden apps), \(plural(tabs, "tab"))", .meta)

    var appOrder: [String] = []
    var perApp: [String: (w: Int, t: Int)] = [:]
    for w in windows {
        if perApp[w.app] == nil { appOrder.append(w.app) }
        perApp[w.app, default: (0, 0)].w += 1
        perApp[w.app, default: (0, 0)].t += w.tabs.count
    }
    appOrder.sort { (perApp[$0]!.t, perApp[$0]!.w) > (perApp[$1]!.t, perApp[$1]!.w) }
    add(appOrder.map { a in
        let c = perApp[a]!
        return "\(a): " + plural(c.w, "window") + (c.t > 0 ? ", " + plural(c.t, "tab") : "")
    }.joined(separator: " · "), .meta)
    for warn in s.warnings { add("! " + warn, .warning) }

    for sec in desktopSections(s, windows) {
        let ws = sec.windows
        let t = ws.reduce(0) { $0 + $1.tabs.count }
        lines += [blank, blank]
        let summaryCounts = plural(ws.count, "window") + (t > 0 ? ", " + plural(t, "tab") : "")
        add(o.markdown ? "\(h2)\(sec.title) — \(summaryCounts)" : "===== \(sec.title) — \(summaryCounts) =====", .section)
        for w in ws {
            lines.append(blank)
            lines += formatWindow(w, o)
        }
    }
    return lines
}

private func groupedByApp(_ ws: [WindowInfo]) -> [WindowInfo] {
    var order: [String] = []
    for w in ws where !order.contains(w.app) { order.append(w.app) }
    return order.flatMap { a in ws.filter { $0.app == a } }
}

private func formatWindow(_ w: WindowInfo, _ o: FormatOptions) -> [StyledLine] {
    var flags: [String] = []
    if !w.tabs.isEmpty { flags.append(plural(w.tabs.count, "tab")) }
    if w.focused { flags.append("Focused") }
    if w.minimized { flags.append("Minimized") }
    if w.appHidden { flags.append("App hidden") }
    var head = w.app
    if !flags.isEmpty { head += " (\(flags.joined(separator: ", ")))" }
    let label = w.tabs.isEmpty ? w.title : (w.note ?? "")
    if !label.isEmpty { head += " — \(label)" } else if w.tabs.isEmpty { head += " — (untitled window)" }
    if w.tabs.isEmpty, let note = w.note { head += " · \(note)" }
    let dim = w.minimized || w.appHidden
    var lines = [StyledLine(text: o.markdown ? "### \(head)" : head, role: .window, focused: w.focused, dim: dim)]
    func tab(_ text: String, _ t: TabInfo, url: String? = nil, path: Bool = false) {
        lines.append(StyledLine(text: text, role: .tab, dim: dim, active: t.active, url: url, isPath: path))
    }

    for t in w.tabs {
        let active = t.active ? " (Active)" : ""
        let link = t.url ?? t.detail
        if o.markdown {
            if o.includeURLs, let url = t.url {
                tab("- [\(t.title.replacingOccurrences(of: "]", with: "\\]"))](\(url))\(active)", t, url: url)
            } else {
                tab("- \(t.title)\(active)" + (o.includeURLs && t.detail != nil ? " — \(t.detail!)" : ""), t)
            }
        } else if !o.includeURLs || link == nil {
            tab("  \(t.title)\(active)", t)
        } else if o.oneLine {
            tab("  \(t.title)\(active) — \(link!)", t, url: t.url)
        } else {
            tab("  \(t.title)\(active)", t)
            lines.append(StyledLine(text: "  \(link!)", role: .link, dim: dim, active: t.active,
                                    url: t.url, isPath: t.url == nil))
        }
    }
    return lines
}

struct DesktopSection {
    var key: String
    var title: String
    var windows: [WindowInfo]
}

func desktopSections(_ s: Snapshot, _ windows: [WindowInfo]) -> [DesktopSection] {
    var out: [DesktopSection] = []
    let known = Set(s.spaces.map(\.id))
    for sp in s.spaces {
        let ws = windows.filter { $0.spaceIDs.count == 1 && $0.spaceIDs[0] == sp.id }
        if !ws.isEmpty { out.append(DesktopSection(key: "space-\(sp.id)", title: s.label(for: sp), windows: groupedByApp(ws))) }
    }
    let sticky = windows.filter { $0.spaceIDs.count > 1 }
    if !sticky.isEmpty { out.append(DesktopSection(key: "sticky", title: "On all desktops", windows: groupedByApp(sticky))) }
    let unknown = windows.filter { $0.spaceIDs.isEmpty || ($0.spaceIDs.count == 1 && !known.contains($0.spaceIDs[0])) }
    if !unknown.isEmpty { out.append(DesktopSection(key: "unknown", title: "Desktop unknown", windows: groupedByApp(unknown))) }
    return out
}
