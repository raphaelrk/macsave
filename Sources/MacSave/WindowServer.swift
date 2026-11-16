import AppKit
import ApplicationServices
import CoreGraphics

// Private SkyLight/CoreGraphics + Accessibility SPI (read-only; widely used by yabai, AltTab, etc.)
typealias CGSConnectionID = Int32
@_silgen_name("CGSMainConnectionID") func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces") func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?
@_silgen_name("CGSCopySpacesForWindows") func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32, _ wids: CFArray) -> CFArray?
@_silgen_name("_AXUIElementGetWindow") func _AXUIElementGetWindow(_ el: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError
@_silgen_name("_AXUIElementCreateWithRemoteToken") func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

// MARK: Spaces

func readSpaces() -> (spaces: [SpaceInfo], displayCount: Int) {
    let cid = CGSMainConnectionID()
    guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return ([], 1) }
    var out: [SpaceInfo] = []
    for (di, d) in displays.enumerated() {
        let current = (d["Current Space"] as? [String: Any]).flatMap(spaceID)
        var desktop = 0
        for s in d["Spaces"] as? [[String: Any]] ?? [] {
            guard let id = spaceID(s) else { continue }
            let fullscreen = (s["type"] as? Int ?? 0) == 4
            if !fullscreen { desktop += 1 }
            out.append(SpaceInfo(id: id, display: di, desktopNumber: fullscreen ? nil : desktop,
                                 fullscreen: fullscreen, current: id == current))
        }
    }
    return (out, max(displays.count, 1))
}

private func spaceID(_ d: [String: Any]) -> UInt64? {
    if let n = d["ManagedSpaceID"] as? NSNumber { return n.uint64Value }
    if let n = d["id64"] as? NSNumber { return n.uint64Value }
    return nil
}

func spacesForWindow(_ wid: CGWindowID) -> [UInt64] {
    let arr = [NSNumber(value: wid)] as CFArray
    guard let r = CGSCopySpacesForWindows(CGSMainConnectionID(), 0x7, arr) as? [NSNumber] else { return [] }
    return r.map(\.uint64Value)
}

// MARK: CoreGraphics window list

struct CGWin {
    var id: CGWindowID
    var pid: pid_t
    var layer: Int
    var bounds: Rect
    var onscreen: Bool
    var name: String?
    var z: Int
}

func readCGWindows() -> [CGWin] {
    let opts: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.enumerated().compactMap { (i, d) in
        guard let id = d[kCGWindowNumber as String] as? CGWindowID,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        let b = d[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return CGWin(id: id, pid: pid, layer: d[kCGWindowLayer as String] as? Int ?? 0,
                     bounds: Rect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0),
                     onscreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false,
                     name: d[kCGWindowName as String] as? String, z: i)
    }
}

// MARK: Accessibility

func axAttr<T>(_ el: AXUIElement, _ attr: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
    return v as? T
}

func axRect(_ el: AXUIElement) -> Rect? {
    var pv: CFTypeRef?, sv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success,
          let pv, let sv, CFGetTypeID(pv) == AXValueGetTypeID(), CFGetTypeID(sv) == AXValueGetTypeID()
    else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p)
    AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return Rect(x: p.x, y: p.y, width: s.width, height: s.height)
}

func axWindowID(_ el: AXUIElement) -> CGWindowID? {
    var wid: CGWindowID = 0
    return _AXUIElementGetWindow(el, &wid) == .success && wid != 0 ? wid : nil
}

private func isRealWindow(_ el: AXUIElement) -> Bool {
    let sub: String? = axAttr(el, kAXSubroleAttribute)
    return sub == kAXStandardWindowSubrole || sub == kAXDialogSubrole
}

/// AXWindows only lists windows on the current Space; windows on other Spaces are reachable
/// by brute-forcing remote element tokens (the technique AltTab uses).
func remoteTokenWindows(pid: pid_t, wanted: Set<CGWindowID>) -> [AXUIElement] {
    var token = Data(count: 20)
    token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
    token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
    token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
    var found: [AXUIElement] = []
    var remaining = wanted
    let start = Date()
    for elementID: UInt64 in 0..<2000 {
        token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
        if let el = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue(),
           let wid = axWindowID(el), remaining.contains(wid), isRealWindow(el) {
            found.append(el)
            remaining.remove(wid)
            if remaining.isEmpty { break }
        }
        if Date().timeIntervalSince(start) > 0.4 { break }
    }
    return found
}

func nativeTabs(_ window: AXUIElement) -> [TabInfo] {
    guard let children: [AXUIElement] = axAttr(window, kAXChildrenAttribute) else { return [] }
    for c in children where (axAttr(c, kAXRoleAttribute) as String?) == kAXTabGroupRole {
        let buttons: [AXUIElement] = axAttr(c, kAXTabsAttribute) ?? axAttr(c, kAXChildrenAttribute) ?? []
        let tabs = buttons.compactMap { b -> TabInfo? in
            guard (axAttr(b, kAXRoleAttribute) as String?) == kAXRadioButtonRole else { return nil }
            let title: String = axAttr(b, kAXTitleAttribute) ?? axAttr(b, kAXDescriptionAttribute) ?? ""
            let selected = (axAttr(b, kAXValueAttribute) as NSNumber?)?.boolValue ?? false
            return TabInfo(title: title, active: selected)
        }
        if tabs.count > 1 { return tabs }
    }
    return []
}

struct AXWin {
    var element: AXUIElement
    var id: CGWindowID?
    var title: String
    var bounds: Rect?
    var minimized: Bool
}

func axWindows(for app: NSRunningApplication, cgCandidates: Set<CGWindowID>) -> [AXWin] {
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(appEl, 1.0)
    var elements: [AXUIElement] = (axAttr(appEl, kAXWindowsAttribute) ?? []).filter(isRealWindow)
    let seen = Set(elements.compactMap(axWindowID))
    let missing = cgCandidates.subtracting(seen)
    if !missing.isEmpty { elements += remoteTokenWindows(pid: app.processIdentifier, wanted: missing) }
    var out: [AXWin] = []
    var ids = Set<CGWindowID>()
    for el in elements {
        let id = axWindowID(el)
        if let id { if ids.contains(id) { continue }; ids.insert(id) }
        out.append(AXWin(element: el, id: id, title: axAttr(el, kAXTitleAttribute) ?? "",
                         bounds: axRect(el),
                         minimized: (axAttr(el, kAXMinimizedAttribute) as NSNumber?)?.boolValue ?? false))
    }
    return out
}

func focusedWindowID() -> CGWindowID? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let el = AXUIElementCreateApplication(app.processIdentifier)
    guard let w: AXUIElement = axAttr(el, kAXFocusedWindowAttribute) else { return nil }
    return axWindowID(w)
}

/// Presses a window's close button via Accessibility (the app shows its own confirmations).
func axCloseWindow(pid: pid_t, wid: CGWindowID) -> Bool {
    let appEl = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(appEl, 2.0)
    let listed: [AXUIElement] = axAttr(appEl, kAXWindowsAttribute) ?? []
    guard let target = listed.first(where: { axWindowID($0) == wid })
            ?? remoteTokenWindows(pid: pid, wanted: [wid]).first else { return false }
    if (axAttr(target, kAXMinimizedAttribute) as NSNumber?)?.boolValue == true {
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }
    guard let button: AXUIElement = axAttr(target, kAXCloseButtonAttribute) else { return false }
    return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
}
