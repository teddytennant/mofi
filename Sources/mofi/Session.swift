import Foundation

/// One open launcher: the modes, the current query and the filtered view.
final class Session {
    let modes: [Mode]
    var current: Int
    var mode: Mode { modes[current] }
    var entries: [Entry] = []
    var filtered: [Int] = []
    var selected = 0
    var scroll = 0
    var query: [Character] = []
    var cursor = 0
    var matcher = Matcher(query: "", matching: .fuzzy, caseMode: .smart)
    var hasIcons = false

    // Per-invocation overrides (CLI flags / mofi.show opts).
    var promptOverride: String?
    var extraMessage: String?
    var errorMessage: String?
    /// Sticky error (config errors); survives reloads, unlike errorMessage.
    var notice: String?
    var linesOverride: Int?
    var autoSelect = false
    var noCustomOverride: Bool?
    var password = false
    var initialRow: Int?
    var matchingOverride: Matching?
    var caseOverride: CaseMode?
    /// Mode names this session was opened with, for hotkey toggling.
    var requestKey = ""

    private var finishHandler: ((Int, String) -> Void)?

    init(modes: [Mode], current: Int, finish: @escaping (Int, String) -> Void) {
        self.modes = modes
        self.current = current
        finishHandler = finish
    }

    var queryString: String { String(query) }
    var prompt: String { promptOverride ?? mode.prompt }
    var message: String? { errorMessage ?? notice ?? mode.message ?? extraMessage }
    var messageIsError: Bool { errorMessage != nil || notice != nil }
    var noCustom: Bool { noCustomOverride ?? mode.noCustom }
    var selectedEntry: Entry? { filtered.indices.contains(selected) ? entries[filtered[selected]] : nil }

    func finish(_ code: Int, _ out: String) {
        let f = finishHandler
        finishHandler = nil
        f?(code, out)
    }

    func loadEntries() {
        errorMessage = nil
        entries = mode.load(query: queryString)
        hasIcons = entries.contains { $0.icon != nil }
        refilter(fromQuery: false)
    }

    func switchMode(by delta: Int) {
        guard modes.count > 1 else { return }
        current = (current + delta + modes.count) % modes.count
        loadEntries()
    }

    func refilter(fromQuery: Bool = true) {
        let cfg = Daemon.shared.config
        let q = queryString
        if mode.dynamic {
            if fromQuery { entries = mode.load(query: q) }
            hasIcons = entries.contains { $0.icon != nil }
            matcher = Matcher(query: "", matching: .fuzzy, caseMode: .smart)
            filtered = Array(entries.indices)
        } else {
            matcher = Matcher(query: q, matching: matchingOverride ?? cfg.matching, caseMode: caseOverride ?? cfg.caseMode)
            let history = Daemon.shared.history
            let usage: (Int) -> Int = mode.sortByUsage ? { [entries, mode] i in history.count(mode.name, entries[i].text) } : { _ in 0 }
            if matcher.isEmpty {
                filtered = Array(entries.indices)
                if mode.sortByUsage {
                    let u = filtered.map(usage)
                    filtered.sort { u[$0] != u[$1] ? u[$0] > u[$1] : $0 < $1 }
                }
            } else {
                var scored: [(Int, Int)] = []
                scored.reserveCapacity(entries.count)
                for i in entries.indices {
                    if let s = matcher.score(entries[i]) { scored.append((i, s)) }
                }
                if cfg.sort {
                    var u: [Int: Int] = [:]
                    if mode.sortByUsage { for (i, _) in scored { u[i] = usage(i) } }
                    scored.sort { a, b in
                        if a.1 != b.1 { return a.1 > b.1 }
                        let ua = u[a.0] ?? 0, ub = u[b.0] ?? 0
                        return ua != ub ? ua > ub : a.0 < b.0
                    }
                }
                filtered = scored.map(\.0)
            }
        }
        selected = 0
        if let r = initialRow {
            initialRow = nil
            if let idx = filtered.firstIndex(of: r) { selected = idx }
        }
        scroll = 0
    }

    func ensureVisible(rows: Int) {
        if selected < scroll { scroll = selected }
        if selected >= scroll + rows { scroll = selected - rows + 1 }
        scroll = max(0, min(scroll, max(0, filtered.count - rows)))
    }
}
