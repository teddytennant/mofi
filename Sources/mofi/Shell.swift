import Foundation

enum Shell {
    /// launchd starts agents with a bare PATH, so borrow the one from the
    /// user's login shell; everything mofi spawns (and Lua's io.popen /
    /// os.execute) inherits it.
    static func setupPath(extra: [String] = []) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let (out, code) = run([shell, "-l", "-c", "printf %s \"$PATH\""], timeout: 3)
        if code == 0, !out.isEmpty { path = out }
        for p in ["/opt/homebrew/bin", "/usr/local/bin", Paths.home + "/.local/bin"] where !path.split(separator: ":").contains(Substring(p)) {
            path += ":" + p
        }
        if !extra.isEmpty { path = extra.map(Paths.expand).joined(separator: ":") + ":" + path }
        setenv("PATH", path, 1)
    }

    static var pathDirs: [String] {
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    /// Fire and forget `/bin/sh -c cmd`.
    static func spawn(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.currentDirectoryURL = URL(fileURLWithPath: Paths.home)
        do { try p.run() } catch { log("exec failed: \(cmd): \(error)") }
    }

    /// Run `/bin/sh -c cmd` and wait; returns stdout and exit status.
    static func capture(_ cmd: String) -> (String, Int32) {
        run(["/bin/sh", "-c", cmd], timeout: nil)
    }

    static func run(_ argv: [String], timeout: TimeInterval?) -> (String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        p.currentDirectoryURL = URL(fileURLWithPath: Paths.home)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return ("", 127) }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }
}
