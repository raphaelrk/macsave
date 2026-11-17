import AppKit
import SwiftUI

/// One row per desktop: its composite on the left, every window's preview on the right.
struct GalleryView: View {
    @ObservedObject var model: Model

    var body: some View {
        let s = model.snapshot!
        let sections = desktopSections(s, s.windows)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Live previews · minimized windows are faded").foregroundColor(.secondary)
                Spacer()
                CloseMinimizedButton(model: model)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12).frame(height: 32)
            .background(Color(hex: 0xF7F7F7))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.key) { sec in
                        GalleryRow(section: sec, stamp: s.date, model: model)
                    }
                }
            }

            HStack {
                Text(model.status).font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Text("\(sections.count) desktops · \(s.windows.count) windows")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(hex: 0xF7F7F7))
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct GalleryRow: View {
    let section: DesktopSection
    let stamp: Date
    @ObservedObject var model: Model

    var body: some View {
        let ws = section.windows
        let tabs = ws.reduce(0) { $0 + $1.tabs.count }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(section.title).fontWeight(.bold)
                Text("\(ws.count) windows · \(tabs) tabs").opacity(0.75)
                Spacer()
            }
            .font(.system(size: 14))
            .foregroundColor(.white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Color(hex: 0x3B3B3B))

            HStack(alignment: .top, spacing: 14) {
                AsyncPreview(id: "\(section.key)@\(stamp.timeIntervalSince1970)") {
                    await Previews.desktop(ws)
                } placeholder: {
                    Text("No preview").font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                }
                .frame(width: 300, height: 188)
                .background(Color(hex: 0x2E2E2E))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 12) {
                    ForEach(Array(ws.enumerated()), id: \.offset) { _, w in
                        WindowCard(window: w, stamp: stamp, model: model)
                    }
                }
            }
            .padding(12)
        }
    }
}

private struct WindowCard: View {
    let window: WindowInfo
    let stamp: Date
    @ObservedObject var model: Model
    @State private var hovering = false
    @State private var enlarged = false
    @State private var image: NSImage?

    var body: some View {
        let w = window
        let faded = w.minimized || w.appHidden
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                AsyncPreview(id: "\(w.windowID ?? 0)@\(stamp.timeIntervalSince1970)", onLoad: { image = $0 }) {
                    guard let wid = w.windowID, !w.minimized || Previews.demo != nil else { return nil }
                    return await Previews.window(wid)
                } placeholder: {
                    VStack(spacing: 4) {
                        if let icon = AppIcons.icon(w) { Image(nsImage: icon).resizable().frame(width: 40, height: 40) }
                        Text(w.minimized ? "Minimized" : "No preview").font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .frame(height: 104)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xEFEFEF))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(w.focused ? Color(hex: 0x5F2AFF) : .clear, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { if image != nil { enlarged = true } }
                .popover(isPresented: $enlarged, arrowEdge: .trailing) {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 720, maxHeight: 480).padding(6)
                    }
                }

                if hovering && Closer.canClose(w) {
                    Button { model.close(w) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)).foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(hex: 0xD93A3A)))
                    }
                    .buttonStyle(.plain).padding(5).help("Close this \(w.app) window")
                }
            }
            HStack(spacing: 5) {
                if let icon = AppIcons.icon(w) { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                Text(w.app).fontWeight(.medium).lineLimit(1)
                if !w.tabs.isEmpty { Text("\(w.tabs.count)").fontWeight(.light).foregroundColor(.secondary) }
            }
            .font(.system(size: 12))
            Text(caption(w)).font(.system(size: 11, weight: .light)).lineLimit(1).truncationMode(.middle)
                .foregroundColor(.ink.opacity(0.75))
        }
        .foregroundColor(.ink)
        .opacity(faded ? 0.4 : 1)
        .help(caption(w))
        .onHover { hovering = $0 }
    }

    private func caption(_ w: WindowInfo) -> String {
        if let t = w.tabs.first(where: \.active) ?? w.tabs.first { return t.title }
        return w.title.isEmpty ? (w.note ?? "") : w.title
    }
}

/// Loads an image once per `id`, showing a spinner and then `placeholder` if nothing came back.
struct AsyncPreview<Placeholder: View>: View {
    let id: String
    var onLoad: (NSImage?) -> Void = { _ in }
    let load: () async -> NSImage?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: NSImage?
    @State private var done = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if done {
                placeholder()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) {
            image = nil
            done = false
            image = await load()
            done = true
            onLoad(image)
        }
    }
}
