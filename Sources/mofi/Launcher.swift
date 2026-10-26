import AppKit

final class LauncherPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the panel and turns input into session changes.
final class Launcher: NSObject, NSWindowDelegate {
    let panel = LauncherPanel()
    let view = LauncherView()
    private(set) var session: Session?
    private var anchor = NSPoint.zero // top-left of the window in screen coords
    private var scrollAccum: CGFloat = 0
    private var cfg: Config { Daemon.shared.config }
    var theme: Theme { cfg.theme }

    override init() {
        super.init()
        view.launcher = self
        panel.contentView = view
        panel.delegate = self
    }

    var visible: Bool { session != nil && panel.isVisible }

    var rows: Int {
        guard let s = session else { return 0 }
        return s.linesOverride ?? theme.lines
    }

    func present(_ s: Session) {
        if let old = session {
            session = nil
            old.finish(1, "")
        }
        session = s
        s.loadEntries()
        if s.autoSelect, s.filtered.count == 1, !s.queryString.isEmpty {
            accept(custom: false, alt: false)
            if session == nil { return }
        }
        position()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(view)
        view.needsDisplay = true
    }

    func cancel() { close(code: 1, out: "") }

    /// Draw a session into a bitmap without ever showing the panel
    /// (used by `mofi -screenshot`).
    func renderOffscreen(_ s: Session, width: CGFloat, scale: CGFloat) -> NSBitmapImageRep {
        session = s
        defer { session = nil }
        s.loadEntries()
        s.ensureVisible(rows: rows)
        let shown = theme.fixedHeight ? rows : min(rows, s.filtered.count)
        let h = view.layout(width: width, rowsShown: shown).height
        view.frame = NSRect(x: 0, y: 0, width: width, height: h)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(h * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: h)
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func close(code: Int, out: String) {
        guard let s = session else { return }
        session = nil
        panel.orderOut(nil)
        s.finish(code, out)
    }

    func windowDidResignKey(_ notification: Notification) {
        if session != nil { cancel() }
    }

    // MARK: geometry

    private func screen() -> NSScreen {
        if cfg.monitor == "primary" { return NSScreen.screens.first ?? NSScreen.main! }
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func position() {
        let sc = screen()
        let vf = sc.visibleFrame
        let w = theme.widthIsPercent ? floor(sc.frame.width * theme.width) : theme.width
        let fullH = view.layout(width: w, rowsShown: rows).height
        let x = floor(vf.midX - w / 2)
        let top: CGFloat
        switch theme.location {
        case "top": top = vf.maxY - theme.yOffset
        case "bottom": top = vf.minY + fullH + theme.yOffset
        default: top = floor(sc.frame.midY + fullH / 2) - theme.yOffset
        }
        anchor = NSPoint(x: x, y: top)
        resize(width: w)
    }

    private func resize(width: CGFloat? = nil) {
        guard let s = session else { return }
        let w = width ?? panel.frame.width
        let shown = theme.fixedHeight ? rows : min(rows, s.filtered.count)
        let h = view.layout(width: w, rowsShown: shown).height
        panel.setFrame(NSRect(x: anchor.x, y: anchor.y - h, width: w, height: h), display: false)
        view.needsDisplay = true
        panel.invalidateShadow()
    }

    private func changed() {
        guard let s = session else { return }
        s.ensureVisible(rows: rows)
        resize()
    }

    // MARK: input

    func key(_ e: NSEvent) {
        guard let s = session else { return }
        let spec = KeySpec(event: e)
        if let name = cfg.customKeys[spec] {
            runCustomKey(name, s)
            return
        }
        if let action = cfg.keymap[spec] {
            perform(action)
            return
        }
        let flags = e.modifierFlags.intersection([.command, .control])
        if flags.isEmpty, let chars = e.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value) }) {
            insert(chars)
        }
    }

    private func insert(_ text: String) {
        guard let s = session else { return }
        let chars = Array(text.replacingOccurrences(of: "\n", with: " "))
        s.query.insert(contentsOf: chars, at: s.cursor)
        s.cursor += chars.count
        queryChanged()
    }

    private func queryChanged() {
        guard let s = session else { return }
        s.refilter()
        if s.autoSelect, s.filtered.count == 1, !s.queryString.isEmpty {
            accept(custom: false, alt: false)
            return
        }
        changed()
    }

    func perform(_ a: KeyAction) {
        guard let s = session else { return }
        let n = s.filtered.count
        switch a {
        case .accept: accept(custom: false, alt: false)
        case .accept_custom: accept(custom: true, alt: false)
        case .accept_alt: accept(custom: false, alt: true)
        case .cancel: cancel()
        case .next: move(1)
        case .prev: move(-1)
        case .page_next: move(rows, clamp: true)
        case .page_prev: move(-rows, clamp: true)
        case .first: if n > 0 { s.selected = 0; changed() }
        case .last: if n > 0 { s.selected = n - 1; changed() }
        case .mode_next: s.switchMode(by: 1); changed()
        case .mode_prev: s.switchMode(by: -1); changed()
        case .delete_entry:
            if let e = s.selectedEntry, s.mode.delete(e) {
                let keep = s.selected
                s.loadEntries()
                s.selected = min(keep, max(0, s.filtered.count - 1))
                changed()
            }
        case .backspace:
            if s.cursor > 0 { s.query.remove(at: s.cursor - 1); s.cursor -= 1; queryChanged() }
        case .delete_char:
            if s.cursor < s.query.count { s.query.remove(at: s.cursor); queryChanged() }
        case .delete_word:
            var i = s.cursor
            while i > 0 && s.query[i - 1] == " " { i -= 1 }
            while i > 0 && s.query[i - 1] != " " { i -= 1 }
            if i < s.cursor { s.query.removeSubrange(i..<s.cursor); s.cursor = i; queryChanged() }
        case .clear_line:
            if !s.query.isEmpty { s.query = []; s.cursor = 0; queryChanged() }
        case .cursor_left: s.cursor = max(0, s.cursor - 1); view.needsDisplay = true
        case .cursor_right: s.cursor = min(s.query.count, s.cursor + 1); view.needsDisplay = true
        case .line_start: s.cursor = 0; view.needsDisplay = true
        case .line_end: s.cursor = s.query.count; view.needsDisplay = true
        case .paste:
            if let t = NSPasteboard.general.string(forType: .string) { insert(t) }
        }
    }

    private func move(_ d: Int, clamp: Bool = false) {
        guard let s = session, !s.filtered.isEmpty else { return }
        let n = s.filtered.count
        var i = s.selected + d
        if clamp || !cfg.cycle {
            i = max(0, min(n - 1, i))
        } else {
            i = ((i % n) + n) % n
        }
        s.selected = i
        changed()
    }

    func accept(custom: Bool, alt: Bool) {
        guard let s = session else { return }
        let entry = custom ? nil : s.selectedEntry
        if let e = entry, e.nonselectable { return }
        if entry == nil && (s.noCustom || s.queryString.isEmpty) { return }
        let mode = s.mode
        if let e = entry, mode.sortByUsage { Daemon.shared.history.bump(mode.name, e.text) }
        switch mode.accept(entry, query: s.queryString, alt: alt) {
        case .close(let out): close(code: 0, out: out)
        case .reload:
            s.query = []
            s.cursor = 0
            s.loadEntries()
            changed()
        case .ignore: break
        case .error(let msg):
            s.errorMessage = msg
            changed()
        }
    }

    private func runCustomKey(_ key: String, _ s: Session) {
        let e = s.selectedEntry
        let idx: Any? = s.mode is LuaMode ? e.map { $0.key + 1 } : nil
        do {
            let r = try Daemon.shared.lua.call("_key", [key, s.mode.name, e?.text, s.queryString, idx], results: 1)
            if r.first as? Bool == true { cancel() } else if session === s { s.loadEntries(); changed() }
        } catch {
            s.errorMessage = "\(error)"
            changed()
        }
    }

    // MARK: mouse

    func hover(_ row: Int?) {
        guard cfg.hoverSelect, let s = session, let r = row, s.scroll + r < s.filtered.count else { return }
        if s.selected != s.scroll + r {
            s.selected = s.scroll + r
            view.needsDisplay = true
        }
    }

    func click(_ row: Int?, count: Int) {
        guard let s = session, let r = row, s.scroll + r < s.filtered.count else { return }
        s.selected = s.scroll + r
        view.needsDisplay = true
        if count >= 2 { accept(custom: false, alt: false) }
    }

    func scrollWheel(_ dy: CGFloat) {
        scrollAccum += dy
        let step: CGFloat = 12
        while abs(scrollAccum) >= step {
            move(scrollAccum > 0 ? -1 : 1, clamp: true)
            scrollAccum -= scrollAccum > 0 ? step : -step
        }
    }
}
