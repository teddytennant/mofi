import AppKit

enum Matching: String { case fuzzy, normal, prefix }
enum CaseMode { case smart, sensitive, insensitive }

/// Swift view of `mofi.config` after init.lua ran. Lua is the source of
/// truth; this is rebuilt on every reload.
struct Config {
    var modi = ["drun", "run", "clipboard", "ssh"]
    var combiModi = ["drun", "run"]
    var display: [String: String] = [:]
    var matching = Matching.fuzzy
    var caseMode = CaseMode.smart
    var sort = true
    var cycle = true
    var hoverSelect = true
    var autoSelect = false
    var monitor = "mouse"
    var extraPath: [String] = []
    var drunPaths: [String] = []
    var drunExclude: Set<String> = []
    var clipEnabled = true
    var clipMax = 500
    var clipPollMs = 250
    var clipImages = true
    var clipPaste = false
    var clipIgnore: Set<String> = []
    var keymap: [KeySpec: KeyAction] = [:]
    var customKeys: [KeySpec: String] = [:]
    var theme = Theme()
    var warnings: [String] = []

    func displayName(_ mode: String) -> String { display[mode] ?? mode }

    static func from(_ d: [String: Any]) -> Config {
        var c = Config()
        if let v = strings(d["modi"]) { c.modi = v }
        if let v = strings(d["combi_modi"]) { c.combiModi = v }
        if let v = d["display"] as? [String: Any] {
            for (k, x) in v { if let s = x as? String { c.display[k] = s } }
        }
        if let s = d["matching"] as? String {
            if let m = Matching(rawValue: s) { c.matching = m } else { c.warnings.append("unknown matching '\(s)'") }
        }
        switch d["case_sensitive"] {
        case let b as Bool: c.caseMode = b ? .sensitive : .insensitive
        default: c.caseMode = .smart
        }
        c.sort = bool(d["sort"]) ?? c.sort
        c.cycle = bool(d["cycle"]) ?? c.cycle
        c.hoverSelect = bool(d["hover_select"]) ?? c.hoverSelect
        c.autoSelect = bool(d["auto_select"]) ?? c.autoSelect
        c.monitor = d["monitor"] as? String ?? c.monitor
        c.extraPath = strings(d["path"]) ?? []
        if let dr = d["drun"] as? [String: Any] {
            c.drunPaths = strings(dr["paths"]) ?? []
            c.drunExclude = Set(strings(dr["exclude"]) ?? [])
        }
        if let cb = d["clipboard"] as? [String: Any] {
            c.clipEnabled = bool(cb["enabled"]) ?? c.clipEnabled
            c.clipMax = int(cb["max_items"]) ?? c.clipMax
            c.clipPollMs = max(50, int(cb["poll_ms"]) ?? c.clipPollMs)
            c.clipImages = bool(cb["images"]) ?? c.clipImages
            c.clipPaste = bool(cb["paste_on_select"]) ?? c.clipPaste
            c.clipIgnore = Set(strings(cb["ignore_apps"]) ?? [])
        }
        if let keys = d["keys"] as? [String: Any] {
            for (name, v) in keys where name != "custom" {
                guard let action = KeyAction(rawValue: name) else {
                    c.warnings.append("keys.\(name): unknown action")
                    continue
                }
                let list = strings(v) ?? (v as? String).map { [$0] } ?? []
                for k in list {
                    if let spec = KeySpec.parse(k) { c.keymap[spec] = action } else { c.warnings.append("keys.\(name): can't parse '\(k)'") }
                }
            }
            if let custom = keys["custom"] as? [String: Any] {
                for k in custom.keys {
                    if let spec = KeySpec.parse(k) { c.customKeys[spec] = k } else { c.warnings.append("keys.custom: can't parse '\(k)'") }
                }
            }
        }
        if let t = d["theme"] as? [String: Any] { c.theme = Theme.from(t) }
        return c
    }
}

struct Theme {
    var font = NSFont.systemFont(ofSize: 14)
    var width: CGFloat = 0.42
    var widthIsPercent = true
    var location = "center"
    var yOffset: CGFloat = 0
    var border: CGFloat = 2
    var radius: CGFloat = 10
    var padding: CGFloat = 16
    var lines = 10
    var fixedHeight = true
    var rowSpacing: CGFloat = 2
    var showIcons = true
    var iconSize: CGFloat = 26
    var showModes = true
    var placeholder = "search…"
    var inputPad = (v: CGFloat(10), h: CGFloat(12))
    var inputRadius: CGFloat = 8
    var inputMargin: CGFloat = 10
    var promptGap: CGFloat = 12
    var elemPad = (v: CGFloat(10), h: CGFloat(14))
    var elemRadius: CGFloat = 8
    var elemSpacing: CGFloat = 12
    var selectedBorder: CGFloat = 3
    var colors = Colors()

    struct Colors {
        var background = NSColor(hex: "#000000")!
        var border = NSColor(hex: "#33ccff")!
        var inputBackground = NSColor(hex: "#292e42")!
        var prompt = NSColor(hex: "#33ccff")!
        var foreground = NSColor(hex: "#c0caf5")!
        var placeholder = NSColor(hex: "#565f89")!
        var caret = NSColor(hex: "#c0caf5")!
        var selectedBackground = NSColor(hex: "#292e42")!
        var selectedForeground = NSColor(hex: "#c0caf5")!
        var selectedBorder = NSColor(hex: "#33ccff")!
        var match = NSColor(hex: "#33ccff")!
        var sub = NSColor(hex: "#565f89")!
        var urgent = NSColor(hex: "#f7768e")!
        var active = NSColor(hex: "#33ccff")!
        var messageBackground = NSColor(hex: "#292e42")!
        var message = NSColor(hex: "#c0caf5")!
        var error = NSColor(hex: "#f7768e")!
    }

    var boldFont: NSFont { NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
    var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    static func from(_ d: [String: Any]) -> Theme {
        var t = Theme()
        let size = cg(d["font_size"]) ?? 14
        if let name = d["font"] as? String {
            t.font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
                ?? NSFont(name: name, size: size)
                ?? NSFont.systemFont(ofSize: size)
        } else {
            t.font = NSFont.systemFont(ofSize: size)
        }
        switch d["width"] {
        case let s as String where s.hasSuffix("%"):
            t.width = (Double(s.dropLast()) ?? 42) / 100
            t.widthIsPercent = true
        case let n?:
            if let w = cg(n) { t.width = w; t.widthIsPercent = false }
        default: break
        }
        t.location = d["location"] as? String ?? t.location
        t.yOffset = cg(d["y_offset"]) ?? t.yOffset
        t.border = cg(d["border"]) ?? t.border
        t.radius = cg(d["radius"]) ?? t.radius
        t.padding = cg(d["padding"]) ?? t.padding
        t.lines = max(1, int(d["lines"]) ?? t.lines)
        t.fixedHeight = bool(d["fixed_height"]) ?? t.fixedHeight
        t.rowSpacing = cg(d["row_spacing"]) ?? t.rowSpacing
        t.showIcons = bool(d["show_icons"]) ?? t.showIcons
        t.iconSize = cg(d["icon_size"]) ?? t.iconSize
        t.showModes = bool(d["show_modes"]) ?? t.showModes
        t.placeholder = d["placeholder"] as? String ?? t.placeholder
        if let i = d["input"] as? [String: Any] {
            if let p = pad(i["padding"]) { t.inputPad = p }
            t.inputRadius = cg(i["radius"]) ?? t.inputRadius
            t.inputMargin = cg(i["margin"]) ?? t.inputMargin
            t.promptGap = cg(i["prompt_gap"]) ?? t.promptGap
        }
        if let e = d["element"] as? [String: Any] {
            if let p = pad(e["padding"]) { t.elemPad = p }
            t.elemRadius = cg(e["radius"]) ?? t.elemRadius
            t.elemSpacing = cg(e["spacing"]) ?? t.elemSpacing
            t.selectedBorder = cg(e["selected_border"]) ?? t.selectedBorder
        }
        if let c = d["colors"] as? [String: Any] {
            func col(_ k: String, _ kp: WritableKeyPath<Colors, NSColor>) {
                if let s = c[k] as? String, let v = NSColor(hex: s) { t.colors[keyPath: kp] = v }
            }
            col("background", \.background)
            col("border", \.border)
            col("input_background", \.inputBackground)
            col("prompt", \.prompt)
            col("foreground", \.foreground)
            col("placeholder", \.placeholder)
            col("caret", \.caret)
            col("selected_background", \.selectedBackground)
            col("selected_foreground", \.selectedForeground)
            col("selected_border", \.selectedBorder)
            col("match", \.match)
            col("sub", \.sub)
            col("urgent", \.urgent)
            col("active", \.active)
            col("message_background", \.messageBackground)
            col("message", \.message)
            col("error", \.error)
        }
        return t
    }
}

// MARK: - loose conversion helpers for Lua-sourced dictionaries

func strings(_ v: Any?) -> [String]? {
    if let a = v as? [Any] { return a.compactMap { $0 as? String } }
    if let s = v as? String { return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    return nil
}

func bool(_ v: Any?) -> Bool? { v as? Bool }

func int(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    return nil
}

func cg(_ v: Any?) -> CGFloat? {
    if let i = v as? Int { return CGFloat(i) }
    if let d = v as? Double { return CGFloat(d) }
    return nil
}

/// `8` or `{ vertical, horizontal }`, like CSS shorthand.
private func pad(_ v: Any?) -> (v: CGFloat, h: CGFloat)? {
    if let n = cg(v) { return (n, n) }
    if let a = v as? [Any], let a0 = cg(a.first) { return (a0, cg(a.count > 1 ? a[1] : nil) ?? a0) }
    return nil
}

extension NSColor {
    /// "#rgb", "#rrggbb", "#rrggbbaa" or "transparent".
    convenience init?(hex: String) {
        if hex == "transparent" || hex == "none" {
            self.init(srgbRed: 0, green: 0, blue: 0, alpha: 0)
            return
        }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let a, r, g, b: UInt64
        if s.count == 8 {
            (r, g, b, a) = (v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
        } else {
            (r, g, b, a) = (v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF, 0xFF)
        }
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}
