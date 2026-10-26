import AppKit

struct AppInfo {
    let name: String
    let path: String
    let bundleID: String
}

/// Installed .app bundles. Scanning is a few ms, so it just rescans in the
/// background when the list is older than a few seconds.
final class AppIndex {
    private(set) var apps: [AppInfo] = []
    private var lastScan = Date.distantPast
    private var scanning = false

    func list(paths: [String], exclude: Set<String>) -> [AppInfo] {
        if apps.isEmpty {
            apps = AppIndex.scan(paths: paths, exclude: exclude)
            lastScan = Date()
        } else if Date().timeIntervalSince(lastScan) > 10 {
            refresh(paths: paths, exclude: exclude)
        }
        return apps
    }

    func refresh(paths: [String], exclude: Set<String>) {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppIndex.scan(paths: paths, exclude: exclude)
            DispatchQueue.main.async {
                self.apps = found
                self.lastScan = Date()
                self.scanning = false
            }
        }
    }

    func find(_ nameOrID: String) -> AppInfo? {
        let q = nameOrID.lowercased()
        return apps.first { $0.bundleID.lowercased() == q || $0.name.lowercased() == q }
    }

    static func scan(paths: [String], exclude: Set<String>) -> [AppInfo] {
        let fm = FileManager.default
        var seen = Set<String>()
        var names = Set<String>()
        var out: [AppInfo] = []

        func add(_ path: String) {
            let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
            let id = info?["CFBundleIdentifier"] as? String ?? path
            let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            if exclude.contains(name) || exclude.contains(id) { return }
            // Same bundle id or same visible name: first path in drun.paths wins.
            if seen.insert(id).inserted, names.insert(name.lowercased()).inserted {
                out.append(AppInfo(name: name, path: path, bundleID: id))
            }
        }

        func walk(_ dir: String, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items where !item.hasPrefix(".") {
                let p = dir + "/" + item
                if item.hasSuffix(".app") {
                    add(p)
                } else if depth < 2 {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue { walk(p, depth: depth + 1) }
                }
            }
        }

        for raw in paths {
            let p = Paths.expand(raw)
            if p.hasSuffix(".app") { if fm.fileExists(atPath: p) { add(p) } } else { walk(p, depth: 0) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Executables on $PATH for the `run` mode.
final class RunIndex {
    private(set) var commands: [String] = []
    private var lastScan = Date.distantPast

    func list() -> [String] {
        if commands.isEmpty || Date().timeIntervalSince(lastScan) > 30 {
            commands = RunIndex.scan()
            lastScan = Date()
        }
        return commands
    }

    static func scan() -> [String] {
        let fm = FileManager.default
        var seen = Set<String>()
        for dir in Shell.pathDirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where !seen.contains(item) {
                let p = dir + "/" + item
                var isDir: ObjCBool = false
                if fm.isExecutableFile(atPath: p), fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue {
                    seen.insert(item)
                }
            }
        }
        return seen.sorted()
    }
}

/// Launch counts so frequently used entries float to the top (rofi's
/// drun/run history).
final class UsageHistory {
    private var counts: [String: Int] = [:]
    private let file = Paths.dataDir + "/history.json"
    private var saveScheduled = false

    init() {
        if let data = FileManager.default.contents(atPath: file),
           let d = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
            counts = d
        }
    }

    func count(_ mode: String, _ text: String) -> Int { counts[mode + "\u{1f}" + text] ?? 0 }

    func bump(_ mode: String, _ text: String) {
        counts[mode + "\u{1f}" + text, default: 0] += 1
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.saveScheduled = false
            Paths.ensure(Paths.dataDir)
            if let data = try? JSONSerialization.data(withJSONObject: self.counts) {
                FileManager.default.createFile(atPath: self.file, contents: data, attributes: [.posixPermissions: 0o600])
            }
        }
    }
}
