import AppKit
import SwiftUI

private let windowPalette: [UInt32] = [0xF5C9CD, 0xF3F8C8, 0xCFE4FF, 0xD5F2D5, 0xEBD9F7, 0xFFE2C4]

private func windowKey(_ w: WindowInfo, _ i: Int) -> String {
    "w-\(w.pid)-\(w.windowID.map(String.init) ?? "i\(i)")"
}

enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ w: WindowInfo) -> NSImage? {
        let key = w.bundleID ?? "pid\(w.pid)"
        if let i = cache[key] { return i }
        let icon = NSRunningApplication(processIdentifier: w.pid)?.icon
            ?? w.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[key] = icon
        return icon
    }
}

private let closeRed = Color(hex: 0xD93A3A)

struct TreeView: View {
    @ObservedObject var model: Model
    private var snapshot: Snapshot { model.snapshot! }
    @State private var search = ""
    @State private var collapsed: Set<String> = []

    private struct Row: Identifiable {
        var id: String
        var window: WindowInfo
        var tabs: [TabInfo]
        var color: Color
    }
    private struct Section: Identifiable {
        var id: String
        var title: String
        var rows: [Row]
        var tabCount: Int
    }

    private var sections: [Section] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        var colorIdx = 0
        return desktopSections(snapshot, snapshot.windows).compactMap { sec in
            let rows: [Row] = sec.windows.enumerated().compactMap { i, w in
                defer { colorIdx += 1 }
                let color = Color(hex: windowPalette[colorIdx % windowPalette.count])
                let key = windowKey(w, i)
                if q.isEmpty { return Row(id: key, window: w, tabs: w.tabs, color: color) }
                let windowHit = [w.app, w.title, w.note ?? ""].contains { $0.lowercased().contains(q) }
                let tabs = windowHit ? w.tabs : w.tabs.filter {
                    [$0.title, $0.url ?? "", $0.detail ?? ""].contains { $0.lowercased().contains(q) }
                }
                return windowHit || !tabs.isEmpty ? Row(id: key, window: w, tabs: tabs, color: color) : nil
            }
            guard !rows.isEmpty else { return nil }
            return Section(id: sec.key, title: sec.title, rows: rows, tabCount: rows.reduce(0) { $0 + $1.tabs.count })
        }
    }

    var body: some View {
        let sections = self.sections
        let searching = !search.isEmpty
        VStack(spacing: 10) {
            TextField("Search…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.ink)
                .padding(.horizontal, 12).frame(height: 40)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 2))

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button("Collapse desktops") { collapsed = Set(sections.map(\.id)) }
                    Button("Collapse windows") {
                        collapsed = Set(sections.flatMap { $0.rows.filter { !$0.tabs.isEmpty }.map(\.id) })
                    }
                    Button("Expand all") { collapsed = [] }
                    Spacer()
                    if searching { Text("filtering — collapse ignored").foregroundColor(.secondary) }
                    CloseMinimizedButton(model: model)
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .padding(.horizontal, 12).frame(height: 32)
                .background(Color(hex: 0xF7F7F7))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { sec in
                            SwiftUI.Section {
                                if searching || !collapsed.contains(sec.id) {
                                    ForEach(sec.rows) { row in
                                        windowHeader(row, open: searching || !collapsed.contains(row.id))
                                        if searching || !collapsed.contains(row.id) {
                                            ForEach(row.tabs.indices.map { "\(row.id)#\($0)" }, id: \.self) { key in
                                                tabRow(row.tabs[Int(key.split(separator: "#").last!)!], row: row)
                                            }
                                        }
                                    }
                                }
                            } header: {
                                desktopHeader(sec, open: searching || !collapsed.contains(sec.id))
                            }
                        }
                    }
                }

                HStack(spacing: 0) {
                    Text(model.status).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                        .padding(.leading, 12)
                    Spacer()
                    let windows = sections.reduce(0) { $0 + $1.rows.count }
                    let tabs = sections.reduce(0) { $0 + $1.tabCount }
                    footerCell("\(sections.count) desktops")
                    footerCell("\(windows) windows")
                    footerCell("\(tabs) tabs")
                }
                .frame(height: 30)
                .background(Color(hex: 0xF7F7F7))
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func toggle(_ key: String) {
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    private func chevron(_ open: Bool) -> some View {
        Image(systemName: open ? "chevron.down" : "chevron.right")
            .font(.system(size: 11, weight: .bold)).frame(width: 16)
    }

    private func desktopHeader(_ sec: Section, open: Bool) -> some View {
        HStack(spacing: 8) {
            chevron(open)
            Text(sec.title).fontWeight(.bold)
            Text("\(sec.rows.count) windows · \(sec.tabCount) tabs").opacity(0.75)
            PreviewEye(help: "Preview this desktop (drawn from its windows)") {
                await Previews.desktop(sec.rows.map(\.window))
            }
            .foregroundColor(.white)
            Spacer()
        }
        .font(.system(size: 14))
        .foregroundColor(.white)
        .padding(.horizontal, 12).frame(height: 34)
        .background(Color(hex: 0x3B3B3B))
        .contentShape(Rectangle())
        .onTapGesture { toggle(sec.id) }
    }

    private func windowHeader(_ row: Row, open: Bool) -> some View {
        let w = row.window
        var flags: [String] = []
        if !w.tabs.isEmpty { flags.append(w.tabs.count == 1 ? "1 tab" : "\(w.tabs.count) tabs") }
        if w.focused { flags.append("Focused") }
        if w.minimized { flags.append("Minimized") }
        if w.appHidden { flags.append("Hidden") }
        let label = w.tabs.isEmpty ? w.title : (w.note ?? "")
        return HStack(spacing: 8) {
            if w.tabs.isEmpty { Spacer().frame(width: 16) } else { chevron(open) }
            if let icon = AppIcons.icon(w) { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(w.app).fontWeight(.medium)
            if let wid = w.windowID, !w.minimized {
                PreviewEye(help: "Preview this window") { await Previews.window(wid) }
            }
            if !flags.isEmpty { Text(flags.joined(separator: " · ")).fontWeight(w.focused ? .bold : .light) }
            Text(label).fontWeight(.light).foregroundColor(.ink.opacity(0.7)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if Closer.canClose(w) { closeButton(help: "Close this \(w.app) window") { model.close(w) } }
        }
        .font(.system(size: 13))
        .foregroundColor(.ink)
        .padding(.horizontal, 12).frame(height: 30)
        .background(row.color)
        .opacity(w.minimized || w.appHidden ? 0.75 : 1)
        .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { if !w.tabs.isEmpty { toggle(row.id) } }
    }

    private func closeButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundColor(closeRed)
                .frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private func tabRow(_ t: TabInfo, row: Row) -> some View {
        let link = t.url ?? t.detail
        let closable = Closer.canCloseTabs(row.window)
        return HStack(spacing: 0) {
            Rectangle().fill(row.color).frame(width: 6)
            Group {
                if t.active, let wid = row.window.windowID, !row.window.minimized {
                    PreviewEye(help: "Preview (only the active tab is rendered)") { await Previews.window(wid) }
                } else {
                    Spacer().frame(width: 22)
                }
            }
            .padding(.leading, 6)
            Text(t.title)
                .fontWeight(t.active ? .semibold : .light)
                .lineLimit(1).truncationMode(.tail)
                .padding(.leading, 2).padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(t.title)
            Group {
                if let link {
                    Text(link)
                        .fontWeight(t.active ? .semibold : .light)
                        .underline(t.url != nil, color: Color.ink.opacity(0.5))
                        .foregroundColor(t.url != nil ? .ink.opacity(0.85) : .ink.opacity(0.55))
                        .lineLimit(1).truncationMode(.middle)
                        .onTapGesture { open(t) }
                        .help(link)
                } else {
                    Text("")
                }
            }
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            if closable {
                closeButton(help: "Close tab") { model.close(row.window, tab: t) }
            } else {
                Spacer().frame(width: 26)
            }
        }
        .padding(.trailing, 12)
        .font(.system(size: 13))
        .foregroundColor(.ink)
        .frame(height: 26)
        .opacity(row.window.minimized || row.window.appHidden ? 0.6 : 1)
        .overlay(Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1), alignment: .bottom)
    }

    private func open(_ t: TabInfo) {
        if let u = t.url, let url = URL(string: u) {
            NSWorkspace.shared.open(url)
        } else if let d = t.detail {
            let path = (d.components(separatedBy: " · ").first! as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }

    private func footerCell(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundColor(.secondary)
            .padding(.horizontal, 14).frame(maxHeight: .infinity)
            .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(width: 1), alignment: .leading)
    }
}

/// Eye icon: hover to peek, click to pin. Loads the image lazily on first open.
struct PreviewEye: View {
    let help: String
    let load: () async -> NSImage?
    @State private var shown = false
    @State private var pinned = false
    @State private var hovering = false
    @State private var image: NSImage?
    @State private var tried = false

    var body: some View {
        Button {
            pinned.toggle()
            shown = pinned
        } label: {
            Image(systemName: pinned ? "eye.fill" : "eye")
                .font(.system(size: 12, weight: .semibold))
                .opacity(hovering || shown ? 1 : 0.55)
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in
            hovering = h
            if h {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if hovering { shown = true } }
            } else if !pinned {
                shown = false
            }
        }
        .popover(isPresented: $shown, arrowEdge: .trailing) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 720, maxHeight: 480)
                } else if tried {
                    Text("No preview available.\nMinimized windows aren't rendered by macOS, and previews need\nScreen Recording permission (System Settings › Privacy & Security).")
                        .font(.system(size: 12)).foregroundColor(.secondary).padding(14)
                } else {
                    ProgressView().frame(width: 240, height: 150)
                }
            }
            .padding(6)
            .task {
                guard image == nil else { return }
                image = await load()
                tried = true
            }
            .onDisappear { pinned = false }
        }
    }
}

/// Two-step button: first click arms it, second click (within 4s) closes every minimized window.
struct CloseMinimizedButton: View {
    @ObservedObject var model: Model
    @State private var armed = false

    var body: some View {
        let n = model.closableMinimized.count
        if n > 0 {
            Button(armed ? "Click again to close \(n) minimized window\(n == 1 ? "" : "s")" : "Close minimized (\(n))") {
                if armed {
                    armed = false
                    model.closeMinimized()
                } else {
                    armed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { armed = false }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: armed ? .bold : .regular))
            .foregroundColor(Color(hex: 0xD93A3A))
            .help("Closes every minimized window (apps may ask about unsaved changes)")
        }
    }
}
