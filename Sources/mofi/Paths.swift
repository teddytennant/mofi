import Foundation

let mofiVersion = "0.1.0"

enum Paths {
    static let home = NSHomeDirectory()

    static var configDir: String {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.config"
        return base + "/mofi"
    }

    static var dataDir: String {
        let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.local/share"
        return base + "/mofi"
    }

    static var initLua: String { configDir + "/init.lua" }
    static var cacheDir: String { home + "/Library/Caches/mofi" }
    static var socket: String { cacheDir + "/mofi.sock" }
    static var log: String { home + "/Library/Logs/mofi.log" }

    static func expand(_ p: String) -> String {
        if p == "~" { return home }
        if p.hasPrefix("~/") { return home + p.dropFirst() }
        return p
    }

    /// mkdir -p with owner-only permissions; history and clipboard live here.
    static func ensure(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(ts) \(msg)\n".data(using: .utf8)!)
}
