import AppKit

enum ModeResult {
    case close(String)   // hide; the string is what the client prints
    case reload          // stay open and reload entries
    case ignore          // nothing happened (e.g. custom text where none is allowed)
    case error(String)   // stay open and show the message
}

protocol Mode: AnyObject {
    var name: String { get }
    var prompt: String { get }
    var message: String? { get }
    var noCustom: Bool { get }
    var sortByUsage: Bool { get }
    /// Entries depend on the query; skip local filtering and reload per keystroke.
    var dynamic: Bool { get }
    func load(query: String) -> [Entry]
    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult
    func delete(_ entry: Entry) -> Bool
}

extension Mode {
    var message: String? { nil }
    var noCustom: Bool { false }
    var sortByUsage: Bool { false }
    var dynamic: Bool { false }
    func delete(_ entry: Entry) -> Bool { false }
}

private var cfg: Config { Daemon.shared.config }

final class DrunMode: Mode {
    let name = "drun"
    var prompt: String { cfg.displayName("drun") }
    var noCustom: Bool { true }
    var sortByUsage: Bool { true }
    private var apps: [AppInfo] = []

    func load(query: String) -> [Entry] {
        apps = Daemon.shared.apps.list(paths: cfg.drunPaths, exclude: cfg.drunExclude)
        return apps.enumerated().map { Entry($1.name, icon: .file($1.path), key: $0) }
    }

    /// Asks a running, scriptable app for a new window so alt-accept doesn't
    /// spawn a second process (and a second Dock icon) per launch.
    private static func newWindow(bundleID: String) -> Bool {
        for verb in ["new window", "make new window"] {
            var err: NSDictionary?
            NSAppleScript(source: "tell application id \"\(bundleID)\" to \(verb)")?.executeAndReturnError(&err)
            if err == nil { return true }
        }
        return false
    }

    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult {
        guard let e = entry else { return .ignore }
        let url = URL(fileURLWithPath: apps[e.key].path)
        if alt, let bid = Bundle(url: url)?.bundleIdentifier,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first {
            // Never fork a second process of an app that is already running:
            // single-process apps (Ghostty, ...) that don't script "new window"
            // would otherwise pile up one Dock icon per press.
            if !Self.newWindow(bundleID: bid) { running.activate() }
            return .close("")
        }
        let conf = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: apps[e.key].path), configuration: conf) { _, err in
            if let err { log("launch failed: \(err.localizedDescription)") }
        }
        return .close("")
    }
}

final class RunMode: Mode {
    let name = "run"
    var prompt: String { cfg.displayName("run") }
    var sortByUsage: Bool { true }

    func load(query: String) -> [Entry] {
        Daemon.shared.runIndex.list().enumerated().map { Entry($1, key: $0) }
    }

    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult {
        let cmd = entry?.text ?? query
        guard !cmd.isEmpty else { return .ignore }
        if alt { Daemon.shared.runInTerminal(cmd) } else { Shell.spawn(cmd) }
        return .close("")
    }
}

final class ClipboardMode: Mode {
    let name = "clipboard"
    var prompt: String { cfg.displayName("clipboard") }
    var noCustom: Bool { true }
    var message: String? { cfg.clipEnabled ? nil : "clipboard history is disabled (clipboard.enabled = false)" }

    func load(query: String) -> [Entry] {
        let store = Daemon.shared.clipboard
        let now = Date().timeIntervalSince1970
        return store.items.enumerated().map { i, item in
            var text = item.text
            if text.utf16.count > 300 { text = String(text.prefix(300)) + "…" }
            text = text.replacingOccurrences(of: "\r\n", with: " ⏎ ").replacingOccurrences(of: "\n", with: " ⏎ ")
                .replacingOccurrences(of: "\t", with: " ")
            var icon: Icon? = nil
            if item.kind == "image", let p = store.imagePath(item) { icon = .image(p) }
            return Entry(text, sub: ClipboardMode.ago(now - item.time), icon: icon, key: i)
        }
    }

    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult {
        guard let e = entry else { return .ignore }
        Daemon.shared.clipboard.copy(e.key)
        // alt (shift-return) inverts paste_on_select for this one pick.
        if cfg.clipPaste != alt {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { ClipboardStore.pasteIntoFrontApp() }
        }
        return .close("")
    }

    func delete(_ entry: Entry) -> Bool {
        Daemon.shared.clipboard.delete(entry.key)
        return true
    }

    static func ago(_ s: Double) -> String {
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m"
        case ..<86400: return "\(Int(s / 3600))h"
        default: return "\(Int(s / 86400))d"
        }
    }
}

/// Several modes in one list (rofi's combi).
final class CombiMode: Mode {
    let name = "combi"
    var prompt: String { cfg.displayName("combi") }
    var sortByUsage: Bool { true }
    var noCustom: Bool { !subs.contains { !$0.noCustom } }
    private let subs: [Mode]
    private var map: [(Int, Entry)] = []

    init(subs: [Mode]) { self.subs = subs }

    func load(query: String) -> [Entry] {
        map = []
        var out: [Entry] = []
        for (si, m) in subs.enumerated() {
            for e in m.load(query: query) {
                var c = Entry(e.text, sub: e.sub ?? m.prompt, icon: e.icon, key: out.count)
                c.urgent = e.urgent
                c.active = e.active
                c.nonselectable = e.nonselectable
                map.append((si, e))
                out.append(c)
            }
        }
        return out
    }

    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult {
        if let entry {
            let (si, e) = map[entry.key]
            return subs[si].accept(e, query: query, alt: alt)
        }
        guard let m = subs.first(where: { !$0.noCustom }) else { return .ignore }
        return m.accept(nil, query: query, alt: alt)
    }

    func delete(_ entry: Entry) -> Bool {
        let (si, e) = map[entry.key]
        return subs[si].delete(e)
    }
}

/// A mode defined in Lua with mofi.mode(name, spec).
final class LuaMode: Mode {
    let name: String
    private(set) var prompt: String
    private(set) var message: String?
    private(set) var noCustom = false
    private(set) var sortByUsage = false
    private(set) var dynamic = false
    private var pending: [Entry]?

    init(name: String) {
        self.name = name
        prompt = cfg.display[name] ?? name
    }

    func load(query: String) -> [Entry] {
        if let p = pending {
            pending = nil
            return p
        }
        do {
            let r = try Daemon.shared.lua.call("_items", [name, query], results: 2)
            return apply(r)
        } catch {
            message = "\(name): \(error)"
            log(message!)
            return []
        }
    }

    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult {
        do {
            let r = try Daemon.shared.lua.call("_select", [name, entry.map { $0.key + 1 }, query, alt], results: 2)
            if r.first as? [Any] != nil || r.first as? [String: Any] != nil {
                pending = apply(r)
                return .reload
            }
            return .close("")
        } catch {
            log("\(name): \(error)")
            return .error("\(error)")
        }
    }

    func delete(_ entry: Entry) -> Bool {
        do {
            let r = try Daemon.shared.lua.call("_delete", [name, entry.key + 1], results: 1)
            return r.first as? Bool ?? false
        } catch {
            message = "\(error)"
            return false
        }
    }

    private func apply(_ r: [Any?]) -> [Entry] {
        if let o = r.count > 1 ? r[1] as? [String: Any] : nil {
            if let p = o["prompt"] as? String { prompt = p }
            message = o["message"] as? String
            noCustom = o["no_custom"] as? Bool ?? false
            sortByUsage = o["sort_by_usage"] as? Bool ?? false
            dynamic = o["dynamic"] as? Bool ?? false
        }
        let list = r.first as? [Any] ?? []
        return list.enumerated().map { i, x in LuaMode.entry(x, key: i) }
    }

    static func entry(_ x: Any, key: Int) -> Entry {
        guard let d = x as? [String: Any] else { return Entry("\(x)", key: key) }
        var e = Entry(d["text"] as? String ?? "", sub: d["sub"] as? String, icon: (d["icon"] as? String).flatMap(Icon.parse), key: key)
        e.urgent = d["urgent"] as? Bool ?? false
        e.active = d["active"] as? Bool ?? false
        e.nonselectable = d["nonselectable"] as? Bool ?? false
        return e
    }
}

/// `mofi -dmenu`: lines from stdin, selection back to stdout.
final class DmenuMode: Mode {
    let name = "dmenu"
    let prompt: String
    let message: String?
    let noCustom: Bool
    let format: String
    private let items: [Entry]

    init(lines: [String], prompt: String, message: String?, noCustom: Bool, format: String) {
        self.prompt = prompt
        self.message = message
        self.noCustom = noCustom
        self.format = format
        items = lines.enumerated().map { i, line in DmenuMode.parseRow(line, key: i) }
    }

    func load(query: String) -> [Entry] { items }

    func accept(_ entry: Entry?, query: String, alt: Bool) -> ModeResult {
        .close(DmenuMode.format(format, entry: entry, query: query))
    }

    /// rofi row options: "text\0icon\x1fname\x1fnonselectable\x1ftrue".
    static func parseRow(_ line: String, key: Int) -> Entry {
        guard let nul = line.firstIndex(of: "\0") else { return Entry(line, key: key) }
        var e = Entry(String(line[..<nul]), key: key)
        let opts = line[line.index(after: nul)...].split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i + 1 < opts.count {
            switch opts[i] {
            case "icon": e.icon = Icon.parse(opts[i + 1])
            case "meta", "info": break
            case "nonselectable": e.nonselectable = opts[i + 1] == "true"
            case "urgent": e.urgent = opts[i + 1] == "true"
            case "active": e.active = opts[i + 1] == "true"
            default: break
            }
            i += 2
        }
        return e
    }

    /// rofi -format: s text, i index, d 1-based index, q quoted text,
    /// f filter, F quoted filter. Other characters pass through.
    static func format(_ f: String, entry: Entry?, query: String) -> String {
        let text = entry?.text ?? query
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        var out = ""
        for ch in f {
            switch ch {
            case "s": out += text
            case "i": out += entry.map { String($0.key) } ?? "-1"
            case "d": out += entry.map { String($0.key + 1) } ?? "0"
            case "q": out += quote(text)
            case "f": out += query
            case "F": out += quote(query)
            default: out.append(ch)
            }
        }
        return out
    }
}
