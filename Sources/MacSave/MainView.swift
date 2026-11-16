import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
    static let headerRed = Color(hex: 0xAE2A3A)
    static let ink = Color(hex: 0x222222)
}

enum Mode: String, CaseIterable {
    case curr, all, min, view
    var scope: Scope { self == .curr ? .current : self == .min ? .minimized : .all }
}

struct MainView: View {
    @ObservedObject var model: Model
    @AppStorage("mode") private var modeRaw = Mode.all.rawValue
    @AppStorage("includeURLs") private var includeURLs = true
    @AppStorage("oneLine") private var oneLine = false
    @AppStorage("markdown") private var markdown = false
    @AppStorage("includeTabless") private var includeTabless = true
    @AppStorage("saveTemplate") private var template = Saver.defaultTemplate
    @AppStorage("saveJSON") private var saveJSON = false
    @AppStorage("aiProvider") private var aiProvider = AIProvider.claude.rawValue
    @State private var showSettings = false
    @State private var copied = false
    @State private var saved = false

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .all }
    private var options: FormatOptions {
        FormatOptions(includeURLs: includeURLs, oneLine: oneLine, markdown: markdown, includeTabless: includeTabless)
    }
    private var lines: [StyledLine] {
        guard let s = model.snapshot else { return [] }
        return styledLines(s, scope: mode == .view ? .all : mode.scope, options: options, summary: model.summary)
    }
    private var text: String { lines.isEmpty ? "" : lines.map(\.text).joined(separator: "\n") + "\n" }
    private var provider: AIProvider? {
        let preferred = AIProvider(rawValue: aiProvider) ?? .claude
        return model.ai[preferred] != nil ? preferred : AIProvider.allCases.first { model.ai[$0] != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if mode == .view {
                    if model.snapshot != nil { TreeView(model: model) } else { loadingView }
                } else {
                    textPane
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(mode == .view ? Color.headerRed : Color.white)

            if mode != .view && (!model.status.isEmpty || model.lastSaved != nil) {
                HStack {
                    Text(model.status).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    Spacer()
                    if let url = model.lastSaved {
                        Button("Reveal \(url.lastPathComponent)") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .buttonStyle(.link).font(.caption)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color.white)
            }

            if mode != .view { footerBar }
        }
        .frame(minWidth: 760, minHeight: 480)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var footerBar: some View {
            HStack(spacing: 0) {
                footer(copied ? "Copied!" : "Copy", bg: 0xF7F7F7, hover: 0xF0F0F0) { copy() }
                footer(saved ? "Saved!" : "Save", bg: 0xC9DEFF, hover: 0xC2D7F8) { save() }
                footer(aiLabel, bg: 0xE6DCFA, hover: 0xDDD0F5) {
                    if let p = provider { model.summarize(text, with: p) }
                }
                .disabled(provider == nil || model.summarizing != nil || model.snapshot == nil)
            }
            .frame(height: 44)
            .overlay(Rectangle().fill(Color(hex: 0xDFDFDF)).frame(height: 1), alignment: .top)
    }

    private var aiLabel: String {
        if let p = model.summarizing { return "Summarizing (\(p.displayName))…" }
        guard let p = provider else { return "AI unavailable" }
        return "Summarize with \(p.displayName)"
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(Array(Mode.allCases.enumerated()), id: \.element) { i, m in
                if i > 0 {
                    Text(m == .view ? "  ⁞⁞  " : "  ::  ").foregroundColor(.white.opacity(0.4))
                }
                Button { modeRaw = m.rawValue } label: {
                    Text(m.rawValue).fontWeight(mode == m ? .bold : .regular).foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if model.loading { ProgressView().controlSize(.small).colorScheme(.dark).padding(.trailing, 10) }
            headerIcon("arrow.clockwise", help: "Rescan") { model.refresh() }
            headerIcon("gearshape", help: "Settings") { showSettings.toggle() }
                .popover(isPresented: $showSettings) { settings }
            Text("macsave").foregroundColor(.white).padding(.leading, 10)
        }
        .font(.system(size: 17))
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Color.headerRed)
    }

    private func headerIcon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).foregroundColor(.white).font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help)
    }

    private var loadingView: some View { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }

    private var textPane: some View {
        ZStack(alignment: .topTrailing) {
            SnapshotTextView(lines: lines)
            if model.snapshot == nil { loadingView }
            VStack(alignment: .leading, spacing: 3) {
                Toggle("URLs / paths", isOn: $includeURLs)
                Toggle("One line", isOn: $oneLine).disabled(markdown)
                Toggle("Markdown", isOn: $markdown)
                Toggle("Windows without tabs", isOn: $includeTabless)
            }
            .toggleStyle(.checkbox)
            .foregroundColor(.ink)
            .padding(6)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xDFDFDF)))
            .padding(.top, 8).padding(.trailing, 14)
        }
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xC3C3C3)))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save path").font(.headline)
            TextField("", text: $template).frame(width: 520).font(.system(.body, design: .monospaced))
            Text("Tokens: {yyyy} {MM} {dd} {HH} {mm} {HHmm}. Next: \(Saver.expand(template).path)")
                .font(.caption).foregroundColor(.secondary)
            Toggle("Also save raw .json snapshot next to it", isOn: $saveJSON)
            Button("Reset path") { template = Saver.defaultTemplate }
            Divider()
            Text("AI summary").font(.headline)
            if model.ai.isEmpty {
                Text("No claude or codex CLI found on your login shell PATH").font(.caption).foregroundColor(.secondary)
            } else {
                Picker("Use", selection: $aiProvider) {
                    ForEach(AIProvider.allCases.filter { model.ai[$0] != nil }) { p in
                        Text("\(p.displayName) — \(abbreviateHome(model.ai[p]!))").tag(p.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Divider()
            Button("Quit MacSave") { NSApp.terminate(nil) }
        }
        .padding(16)
    }

    private func footer(_ title: String, bg: UInt32, hover: UInt32, action: @escaping () -> Void) -> some View {
        FooterButton(title: title, bg: Color(hex: bg), hover: Color(hex: hover), action: action)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rich = styledText(lines)
        if let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
    }

    private func save() {
        guard let s = model.snapshot else { return }
        do {
            let url = try Saver.save(text, snapshot: s, template: template, json: saveJSON)
            model.lastSaved = url
            model.status = "Saved \(abbreviateHome(url.path))"
            saved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { saved = false }
        } catch {
            model.status = "Save failed: \(error.localizedDescription)"
        }
    }
}

struct FooterButton: View {
    let title: String
    let bg: Color
    let hover: Color
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold)).textCase(.uppercase)
                .foregroundColor(Color.ink.opacity(enabled ? 1 : 0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hovering && enabled ? hover : bg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SnapshotTextView: NSViewRepresentable {
    let lines: [StyledLine]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .white
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = true
        tv.backgroundColor = .white
        tv.textContainerInset = NSSize(width: 14, height: 14)
        tv.isHorizontallyResizable = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.linkTextAttributes = [.foregroundColor: StyleColors.link, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                 .cursor: NSCursor.pointingHand]
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        let rich = styledText(lines)
        guard tv.attributedString() != rich else { return }
        tv.textStorage?.setAttributedString(rich)
    }
}

enum StyleColors {
    static let ink = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.13, alpha: 1)
    static let focused = NSColor(srgbRed: 0x5f / 255.0, green: 0x2a / 255.0, blue: 1, alpha: 1)
    static let link = NSColor(srgbRed: 0, green: 0, blue: 0.93, alpha: 1)
    static let path = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.40, alpha: 1)
    static let section = NSColor(srgbRed: 0xAE / 255.0, green: 0x2A / 255.0, blue: 0x3A / 255.0, alpha: 1)
    static let warning = NSColor(srgbRed: 0.71, green: 0.33, blue: 0.04, alpha: 1)
    static let summary = NSColor(srgbRed: 0.32, green: 0.20, blue: 0.55, alpha: 1)
}

/// Tabsave-style rendering: bold window headers (purple when focused), active tabs bold,
/// blue underlined clickable URLs, grey paths, minimized/hidden windows faded.
func styledText(_ lines: [StyledLine]) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let size: CGFloat = 13
    let para = NSMutableParagraphStyle()
    para.lineSpacing = 2.5
    for (i, l) in lines.enumerated() {
        var font = NSFont.systemFont(ofSize: size, weight: .light)
        var color = StyleColors.ink
        switch l.role {
        case .title: font = .systemFont(ofSize: size, weight: .regular)
        case .meta, .blank: font = .systemFont(ofSize: size, weight: .regular)
        case .summary: font = .systemFont(ofSize: size, weight: .regular); color = StyleColors.summary
        case .warning: font = .systemFont(ofSize: size - 1, weight: .regular); color = StyleColors.warning
        case .section: font = .systemFont(ofSize: size + 2, weight: .bold); color = StyleColors.section
        case .window:
            font = .systemFont(ofSize: size, weight: l.focused ? .heavy : .semibold)
            if l.focused { color = StyleColors.focused }
        case .tab: font = .systemFont(ofSize: size, weight: l.active ? .bold : .light)
        case .link:
            font = .systemFont(ofSize: size, weight: l.active ? .semibold : .light)
            color = l.isPath ? StyleColors.path : StyleColors.link
        }
        if l.dim { color = color.withAlphaComponent(0.4) }
        let piece = NSMutableAttributedString(string: l.text + (i < lines.count - 1 ? "\n" : ""), attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: para,
        ])
        if let url = l.url, let u = URL(string: url) {
            let r = (l.text as NSString).range(of: url, options: .backwards)
            if r.location != NSNotFound {
                piece.addAttributes([.link: u, .foregroundColor: StyleColors.link.withAlphaComponent(l.dim ? 0.4 : 1),
                                     .underlineStyle: NSUnderlineStyle.single.rawValue], range: r)
            }
        }
        out.append(piece)
    }
    return out
}
