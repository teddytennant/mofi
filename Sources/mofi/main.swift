import AppKit

let usage = """
mofi \(mofiVersion) — a fast rofi-style launcher for macOS

usage:
  mofi -show MODE [-modi a,b,c]   open a mode (drun, run, clipboard, ssh, combi, or a Lua mode)
  mofi -dmenu [options]           pick a line from stdin, print it to stdout
  mofi -e MESSAGE                 show a message
  mofi -lua CODE                  run Lua inside the daemon and print the result
  mofi -reload | -quit | -status  control the daemon
  mofi -check                     load the config and report errors, without the daemon
  mofi -init                      write a starter ~/.config/mofi/init.lua
  mofi -dump-defaults             print the built-in Lua runtime and defaults
  mofi -filter QUERY              rank stdin against QUERY and print matches (no UI)
  mofi -install-agent             start the daemon at login (LaunchAgent)
  mofi -uninstall-agent           remove the LaunchAgent
  mofi daemon                     run the daemon in the foreground

-show / -dmenu options:
  -p, -prompt TEXT        prompt text
  -l, -lines N            number of rows
  -mesg TEXT              message shown under the input
  -filter TEXT            initial query
  -auto-select            accept as soon as one entry is left
  -no-custom              only allow picking listed entries (alias -only-match)
  -format FMT             dmenu output: s text, i index, d 1-based, q quoted, f/F query
  -selected-row N         preselect row N (0-based)
  -sep CHAR               dmenu input separator (default newline)
  -i / -case-sensitive    force case-insensitive / case-sensitive matching
  -matching MODE          fuzzy | normal | prefix
  -password               hide typed text

exit status: 0 picked, 1 cancelled, 2 error.
docs: https://github.com/teddytennant/mofi/tree/main/docs
"""

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("mofi: \(msg)\n".data(using: .utf8)!)
    exit(2)
}

// MARK: daemon management

let agentLabel = "io.github.teddytennant.mofi"
var agentPlist: String { Paths.home + "/Library/LaunchAgents/\(agentLabel).plist" }

func executablePath() -> String {
    URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().path
}

func spawnDaemon() {
    var pid: pid_t = 0
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
    var fa: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fa)
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&fa, 1, Paths.log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    posix_spawn_file_actions_addopen(&fa, 2, Paths.log, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    let exe = executablePath()
    let argv: [UnsafeMutablePointer<CChar>?] = [strdup(exe), strdup("daemon"), nil]
    posix_spawn(&pid, exe, &fa, &attr, argv, environ)
    posix_spawn_file_actions_destroy(&fa)
    posix_spawnattr_destroy(&attr)
}

/// Talk to the daemon, starting it first if nothing is listening.
func send(_ req: [String: Any], autostart: Bool = true) -> [String: Any] {
    if let r = IPC.request(req) { return r }
    guard autostart else { fail("daemon is not running") }
    // A crashed daemon can leave the socket file; spawning replaces it.
    spawnDaemon()
    for _ in 0..<100 {
        usleep(50_000)
        if IPC.alive() { break }
    }
    guard let r = IPC.request(req) else { fail("couldn't start the daemon; see \(Paths.log)") }
    return r
}

func waitUntilGone() {
    for _ in 0..<40 {
        if !IPC.alive() { return }
        usleep(50_000)
    }
}

func finish(_ r: [String: Any]) -> Never {
    let code = r["code"] as? Int ?? 2
    let out = r["out"] as? String ?? ""
    if !out.isEmpty {
        let h = code == 2 ? FileHandle.standardError : FileHandle.standardOutput
        h.write((out + "\n").data(using: .utf8)!)
    }
    exit(Int32(code))
}

func launchctl(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = args
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

func installAgent() {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key><string>\(agentLabel)</string>
      <key>ProgramArguments</key><array><string>\(executablePath())</string><string>daemon</string></array>
      <key>RunAtLoad</key><true/>
      <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
      <key>ProcessType</key><string>Interactive</string>
      <key>StandardOutPath</key><string>\(Paths.log)</string>
      <key>StandardErrorPath</key><string>\(Paths.log)</string>
    </dict>
    </plist>

    """
    Paths.ensure((agentPlist as NSString).deletingLastPathComponent)
    FileManager.default.createFile(atPath: agentPlist, contents: plist.data(using: .utf8))
    if IPC.request(["cmd": "quit"]) != nil {
        waitUntilGone()
    }
    let domain = "gui/\(getuid())"
    launchctl(["bootout", "\(domain)/\(agentLabel)"])
    launchctl(["bootstrap", domain, agentPlist])
    print("installed \(agentPlist); the daemon now starts at login")
}

func uninstallAgent() {
    launchctl(["bootout", "gui/\(getuid())/\(agentLabel)"])
    try? FileManager.default.removeItem(atPath: agentPlist)
    print("removed \(agentPlist)")
}

func runDaemon() -> Never {
    if IPC.alive() { fail("already running") }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let d = Daemon()
    Daemon.shared = d
    app.delegate = d
    app.run()
    exit(0)
}

// MARK: argument parsing

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "daemon" || args.first == "--daemon" || args.first == "-daemon" { runDaemon() }
if args.isEmpty {
    print(usage)
    exit(0)
}

var show: String?
var modi: [String]?
var dmenu = false
var opts: [String: Any] = [:]
var sep = "\n"
var luaCode: String?
var message: String?
var filterQuery: String?
var command: String?
var screenshotOut: String?

/// Flags rofi accepts that mofi doesn't need; taken (with their value) and ignored.
let ignoredWithValue: Set<String> = [
    "theme", "theme-str", "font", "width", "location", "monitor", "window-title", "config",
    "display-columns", "display-column-separator", "icon-theme", "xoffset", "yoffset", "ellipsize-mode",
    "drun-display-format", "drun-categories", "run-command", "run-shell-command", "ssh-command",
    "terminal", "padding", "dpi", "scroll-method", "kb-custom-1", "eh", "keep-right",
]
let ignoredFlags: Set<String> = [
    "show-icons", "no-show-icons", "markup-rows", "markup", "no-fixed-num-lines", "fixed-num-lines",
    "no-lazy-grab", "normal-window", "steal-focus", "no-config", "click-to-exit", "no-click-to-exit",
    "sort", "no-sort", "sync", "async-pre-read", "disable-history", "no-disable-history", "tokenize",
    "no-tokenize", "hover-select", "no-hover-select", "insensitive",
]

var i = 0
func next(_ flag: String) -> String {
    i += 1
    guard i < args.count else { fail("\(flag) needs a value") }
    return args[i]
}

while i < args.count {
    var a = args[i]
    if a.hasPrefix("--") { a.removeFirst() }
    switch a {
    case "-h", "-help": print(usage); exit(0)
    case "-v", "-version": print("mofi \(mofiVersion)"); exit(0)
    case "-show": show = next(a)
    case "-modi", "-modes": modi = next(a).split(separator: ",").map(String.init)
    case "-combi-modi": opts["combi_modi"] = next(a)
    case "-dmenu": dmenu = true
    case "-p", "-prompt": opts["prompt"] = next(a)
    case "-l", "-lines": opts["lines"] = Int(next(a)) ?? 10
    case "-mesg": opts["message"] = next(a)
    case "-filter": filterQuery = next(a)
    case "-auto-select": opts["auto_select"] = true
    case "-no-auto-select": opts["auto_select"] = false
    case "-no-custom", "-only-match": opts["no_custom"] = true
    case "-format": opts["format"] = next(a)
    case "-selected-row": opts["selected_row"] = Int(next(a)) ?? 0
    case "-sep": sep = next(a)
    case "-i", "-case-insensitive": opts["case_sensitive"] = false
    case "-case-sensitive": opts["case_sensitive"] = true
    case "-matching": opts["matching"] = next(a)
    case "-password": opts["password"] = true
    case "-e": message = next(a)
    case "-lua": luaCode = next(a)
    case "-screenshot": screenshotOut = next(a)
    case "-reload", "-quit", "-status", "-check", "-init", "-dump-defaults", "-install-agent", "-uninstall-agent":
        command = a
    case "-multi-select":
        FileHandle.standardError.write("mofi: -multi-select isn't supported; single selection only\n".data(using: .utf8)!)
    default:
        let name = String(a.drop { $0 == "-" })
        if ignoredWithValue.contains(name) || name.hasPrefix("kb-") || name.hasPrefix("me-") || name.hasPrefix("display-") {
            _ = next(a)
        } else if !ignoredFlags.contains(name) {
            FileHandle.standardError.write("mofi: ignoring unknown option \(args[i])\n".data(using: .utf8)!)
        }
    }
    i += 1
}

// MARK: local commands (no daemon)

switch command {
case "-dump-defaults":
    print(defaultsLua)
    exit(0)
case "-init":
    let path = Paths.initLua
    if FileManager.default.fileExists(atPath: path) { fail("\(path) already exists") }
    try? FileManager.default.createDirectory(atPath: Paths.configDir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: path, contents: starterConfig.data(using: .utf8))
    print("wrote \(path)")
    exit(0)
case "-check":
    let d = Daemon(checkOnly: true)
    Daemon.shared = d
    if let e = d.reload() { fail(e) }
    let c = d.config
    print("ok: \(Paths.initLua)")
    print("  modi: \(c.modi.joined(separator: ", "))")
    print("  keys: \(c.keymap.count) bindings, \(c.customKeys.count) custom")
    exit(0)
case "-install-agent": installAgent(); exit(0)
case "-uninstall-agent": uninstallAgent(); exit(0)
case "-status": finish(send(["cmd": "ping"], autostart: false))
case "-quit":
    if IPC.request(["cmd": "quit"]) != nil {
        // Wait for it to go away so a following start doesn't race it.
        waitUntilGone()
    }
    exit(0)
case "-reload": finish(send(["cmd": "reload"]))
default: break
}

if let code = luaCode { finish(send(["cmd": "lua", "code": code])) }
if let m = message { finish(send(["cmd": "error", "message": m])) }

func readItems() -> [String] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    var s = String(decoding: data, as: UTF8.self)
    let sepStr = sep == "\\0" ? "\0" : sep == "\\n" ? "\n" : sep
    if s.hasSuffix(sepStr) { s.removeLast(sepStr.count) }
    if s.isEmpty { return [] }
    return s.components(separatedBy: sepStr)
}

if let q = filterQuery, !dmenu, show == nil {
    // Headless ranking, like `fzf --filter`.
    let entries = readItems().enumerated().map { Entry($1, key: $0) }
    var m: Matching = .fuzzy
    if let s = opts["matching"] as? String, let mm = Matching(rawValue: s) { m = mm }
    let cm: CaseMode = (opts["case_sensitive"] as? Bool).map { $0 ? .sensitive : .insensitive } ?? .smart
    let matcher = Matcher(query: q, matching: m, caseMode: cm)
    let ranked = entries.compactMap { e in matcher.score(e).map { (e, $0) } }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.key < $1.0.key }
    for (e, _) in ranked { print(e.text) }
    exit(ranked.isEmpty ? 1 : 0)
}

if let f = filterQuery { opts["filter"] = f }

if let out = screenshotOut {
    Screenshot.run(out: out, names: modi ?? (show.map { [$0] } ?? []), start: show, opts: opts, dmenu: dmenu ? readItems() : nil)
}

if dmenu {
    let items = readItems()
    finish(send(["cmd": "dmenu", "items": items, "opts": opts]))
}

if let mode = show {
    var req: [String: Any] = ["cmd": "show", "mode": mode, "opts": opts]
    if let modi { req["modi"] = modi }
    finish(send(req))
}

print(usage)
exit(0)
