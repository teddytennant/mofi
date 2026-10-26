import Foundation

enum Icon {
    case file(String)   // icon Finder would show for this path (apps included)
    case image(String)  // an image file drawn as-is
    case symbol(String) // SF Symbol name
    case named(String)  // NSImage(named:)

    /// Lua/dmenu icon spec: "sf:bolt", "app:Safari", "/path/to/file", "~/x.png".
    static func parse(_ s: String) -> Icon? {
        if s.isEmpty { return nil }
        if s.hasPrefix("sf:") { return .symbol(String(s.dropFirst(3))) }
        if s.hasPrefix("app:") {
            let name = String(s.dropFirst(4))
            if let app = Daemon.shared?.apps.find(name) { return .file(app.path) }
            return nil
        }
        if s.hasPrefix("/") || s.hasPrefix("~") {
            let p = Paths.expand(s)
            let ext = (p as NSString).pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "gif", "tiff", "heic", "icns", "pdf", "svg", "webp"].contains(ext) ? .image(p) : .file(p)
        }
        return .named(s)
    }
}

struct Entry {
    var text: String
    var sub: String?
    var icon: Icon?
    var urgent = false
    var active = false
    var nonselectable = false
    /// Index into the owning mode's own item list.
    var key: Int
    let u16: [UInt16]
    let low: [UInt16]

    init(_ text: String, sub: String? = nil, icon: Icon? = nil, key: Int) {
        self.text = text
        self.sub = sub
        self.icon = icon
        self.key = key
        u16 = Array(text.utf16)
        low = u16.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
    }
}

/// Scores entries against a query. Space-separated tokens must all match
/// (rofi's `tokenize`). Works on UTF-16 so match positions map straight
/// onto NSAttributedString ranges for highlighting.
struct Matcher {
    let matching: Matching
    let caseSensitive: Bool
    let tokens: [[UInt16]]

    init(query: String, matching: Matching, caseMode: CaseMode) {
        self.matching = matching
        switch caseMode {
        case .sensitive: caseSensitive = true
        case .insensitive: caseSensitive = false
        case .smart: caseSensitive = query.contains { $0.isUppercase }
        }
        let cs = caseSensitive
        tokens = query.split(separator: " ").map { tok in
            let u = Array(tok.utf16)
            return cs ? u : u.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
        }
    }

    var isEmpty: Bool { tokens.isEmpty }

    func score(_ e: Entry) -> Int? {
        var pos: [Int]? = nil
        return run(e, &pos)
    }

    func positions(_ e: Entry) -> [Int] {
        var pos: [Int]? = []
        _ = run(e, &pos)
        return pos ?? []
    }

    private func run(_ e: Entry, _ pos: inout [Int]?) -> Int? {
        let hay = caseSensitive ? e.u16 : e.low
        var total = 0
        for t in tokens {
            let s: Int?
            switch matching {
            case .fuzzy: s = Matcher.fuzzy(t, hay, e.u16, &pos)
            case .normal: s = Matcher.substring(t, hay, e.u16, wordStartOnly: false, &pos)
            case .prefix: s = Matcher.substring(t, hay, e.u16, wordStartOnly: true, &pos)
            }
            guard let s else { return nil }
            total += s
        }
        // Prefer shorter candidates on ties ("Safari" over "Safari Technology Preview").
        return total - min(hay.count, 64) / 4
    }

    private static func isSep(_ c: UInt16) -> Bool {
        switch c {
        case 32, 45, 95, 46, 47, 58, 40, 41, 91, 93, 44, 9: return true // space - _ . / : ( ) [ ] , tab
        default: return false
        }
    }

    private static func isUpper(_ c: UInt16) -> Bool { c >= 65 && c <= 90 }
    private static func isLower(_ c: UInt16) -> Bool { c >= 97 && c <= 122 }

    private static func boundary(_ orig: [UInt16], _ j: Int) -> Int {
        if j == 0 { return 12 }
        let p = orig[j - 1], c = orig[j]
        if isSep(p) { return 10 }
        if isLower(p) && isUpper(c) { return 8 }
        return 0
    }

    /// fzf v1 style: find the leftmost match end, walk back to the tightest
    /// start, then score that window.
    static func fuzzy(_ p: [UInt16], _ t: [UInt16], _ orig: [UInt16], _ pos: inout [Int]?) -> Int? {
        let m = p.count, n = t.count
        if m == 0 { return 0 }
        if m > n { return nil }
        var pi = 0
        var end = -1
        for i in 0..<n where t[i] == p[pi] {
            pi += 1
            if pi == m { end = i; break }
        }
        if end < 0 { return nil }
        pi = m - 1
        var start = end
        var i = end
        while i >= 0 {
            if t[i] == p[pi] {
                pi -= 1
                if pi < 0 { start = i; break }
            }
            i -= 1
        }
        var score = 0
        var prev = -2
        var run = 0
        pi = 0
        for j in start...end where pi < m && t[j] == p[pi] {
            var s = 16 + boundary(orig, j)
            if prev == j - 1 {
                run += 1
                s += 8 + min(run, 3) * 2
            } else {
                run = 0
                if prev >= 0 { s -= min(3 + (j - prev - 1), 12) }
            }
            score += s
            prev = j
            pos?.append(j)
            pi += 1
        }
        return score - min(start, 15)
    }

    static func substring(_ p: [UInt16], _ t: [UInt16], _ orig: [UInt16], wordStartOnly: Bool, _ pos: inout [Int]?) -> Int? {
        let m = p.count, n = t.count
        if m == 0 { return 0 }
        if m > n { return nil }
        var best: (Int, Int)? = nil
        var i = 0
        while i + m <= n {
            if t[i] == p[0] && (!wordStartOnly || i == 0 || isSep(orig[i - 1]) || (isLower(orig[i - 1]) && isUpper(orig[i]))) {
                var k = 1
                while k < m && t[i + k] == p[k] { k += 1 }
                if k == m {
                    let s = 16 * m + 8 * (m - 1) + boundary(orig, i) - min(i, 15)
                    if best == nil || s > best!.1 { best = (i, s) }
                    if boundary(orig, i) > 0 { break }
                }
            }
            i += 1
        }
        guard let (at, s) = best else { return nil }
        if pos != nil { pos!.append(contentsOf: at..<(at + m)) }
        return s
    }
}
