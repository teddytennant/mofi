import AppKit

/// The resident process: owns the Lua VM, the panel, the indexes and the
/// clipboard watcher. Clients (`mofi -show`, `mofi -dmenu`, hotkeys) only
/// ask it to show things, which is why opening is instant.
final class Daemon: NSObject, NSApplicationDelegate {
    static var shared: Daemon!

    private(set) var lua = LuaVM()
    private(set) var config = Config()
    let checkOnly: Bool
    lazy var launcher = Launcher()
    let clipboard = ClipboardStore()
    let apps = AppIndex()
    let runIndex = RunIndex()
    let history = UsageHistory()
    private(set) var configError: String?
    private var server: IPCServer?
    private var watcher: DispatchSourceFileSystemObject?
    private var configStamp = ""
    private var reloadScheduled = false
    private var combiOverride: [String]?

    init(checkOnly: Bool = false) {
        self.checkOnly = checkOnly
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        Shell.setupPath()
        HotKeys.shared.install()
        HotKeys.shared.handler = { [weak self] id in self?.hotkey(id) }
        reload()
        apps.refresh(paths: config.drunPaths, exclude: config.drunExclude)
        DispatchQueue.global(qos: .utility).async { [runIndex] in _ = runIndex.list() }
        server = IPCServer(path: Paths.socket) { [weak self] req, reply in self?.handle(req, reply) }
        do {
            try server?.start()
        } catch {
            log("ipc: \(error)")
            exit(1)
        }
        watchConfig()
        log("mofi \(mofiVersion) ready (pid \(getpid()))")
    }

    func applicationWillTerminate(_ notification: Notification) { server?.stop() }

    // MARK: config

    /// Build a fresh VM, run the built-in runtime then the user's init.lua.
    @discardableResult
    func reload() -> String? {
        HotKeys.shared.unregisterAll()
        HotKeys.shared.dryRun = checkOnly
        let vm = LuaVM()
        LuaAPI.install(vm)
        lua = vm
        configError = nil
        do {
            try vm.exec(defaultsLua, name: "mofi/defaults.lua")
        } catch {
            configError = "built-in runtime failed: \(error)"
        }
        if configError == nil, FileManager.default.fileExists(atPath: Paths.initLua) {
            do { try vm.execFile(Paths.initLua) } catch { configError = "\(error)" }
        }
        config = Config.from(vm.global("mofi.config") as? [String: Any] ?? [:])
        if !config.warnings.isEmpty {
            let w = "config: " + config.warnings.joined(separator: "; ")
            configError = configError.map { $0 + "\n" + w } ?? w
        }
        configStamp = stamp()
        guard !checkOnly else { return configError }
        if !config.extraPath.isEmpty { Shell.setupPath(extra: config.extraPath) }
        clipboard.configure(config)
        launcher.view.clearIconCache()
        if let e = configError { log("config error: \(e)") } else { log("config loaded") }
        return configError
    }

    /// mtimes of the config dir's Lua files; editors that save by rename
    /// don't fire vnode events on the file itself, so compare on show too.
    private func stamp() -> String {
        let dir = URL(fileURLWithPath: Paths.configDir).resolvingSymlinksInPath().path
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return "" }
        return items.filter { $0.hasSuffix(".lua") }.sorted().map { f -> String in
            let p = URL(fileURLWithPath: dir + "/" + f).resolvingSymlinksInPath().path
            let m = (try? FileManager.default.attributesOfItem(atPath: p)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(f)=\(m)"
        }.joined(separator: ",")
    }

    private func reloadIfChanged() {
        if stamp() != configStamp { reload() }
    }

    private func watchConfig() {
        let dir = URL(fileURLWithPath: Paths.configDir).resolvingSymlinksInPath().path
        let fd = open(dir, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self, !self.reloadScheduled else { return }
            self.reloadScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.reloadScheduled = false
                self.reloadIfChanged()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    // MARK: actions

    private func hotkey(_ id: UInt32) {
        do { try lua.call("_hotkey", [Int(id)], results: 0) } catch { showError("\(error)") }
    }

    func runInTerminal(_ cmd: String) {
        do { try lua.call("terminal", [cmd], results: 0) } catch { log("terminal: \(error)") }
    }

    func makeMode(_ name: String) -> Mode? {
        switch name {
        case "drun": return DrunMode()
        case "run": return RunMode()
        case "clipboard": return ClipboardMode()
        case "combi": return CombiMode(subs: (combiOverride ?? config.combiModi).filter { $0 != "combi" }.compactMap(makeMode))
        default:
            let r = try? lua.call("_has_mode", [name], results: 1)
            return r?.first as? Bool == true ? LuaMode(name: name) : nil
        }
    }

    /// Open modes (first one that resolves wins focus unless `start` is given).
    func show(_ names: [String], start: String? = nil, opts: [String: Any] = [:], finish: @escaping (Int, String) -> Void) {
        reloadIfChanged()
        combiOverride = strings(opts["combi_modi"])
        defer { combiOverride = nil }
        var modes: [Mode] = []
        var current = 0
        for n in names {
            guard let m = makeMode(n) else {
                if n != "window" { log("unknown mode '\(n)'") }
                continue
            }
            if n == start { current = modes.count }
            modes.append(m)
        }
        if let start, !names.contains(start), let m = makeMode(start) {
            current = modes.count
            modes.append(m)
        }
        guard !modes.isEmpty else {
            finish(2, "unknown mode: \(start ?? names.joined(separator: ","))")
            return
        }
        let key = names.joined(separator: ",") + "|" + (start ?? "")
        if launcher.visible, launcher.session?.requestKey == key, opts["filter"] == nil {
            launcher.cancel() // same hotkey again toggles it closed
            finish(1, "")
            return
        }
        let s = Session(modes: modes, current: current, finish: finish)
        s.requestKey = key
        apply(opts, to: s)
        present(s)
    }

    private func apply(_ o: [String: Any], to s: Session) {
        s.promptOverride = o["prompt"] as? String
        s.extraMessage = o["message"] as? String
        s.linesOverride = int(o["lines"])
        s.autoSelect = o["auto_select"] as? Bool ?? config.autoSelect
        s.noCustomOverride = o["no_custom"] as? Bool
        s.password = o["password"] as? Bool ?? false
        s.initialRow = int(o["selected_row"])
        if let m = o["matching"] as? String { s.matchingOverride = Matching(rawValue: m) }
        if let c = o["case_sensitive"] as? Bool { s.caseOverride = c ? .sensitive : .insensitive }
        if let f = o["filter"] as? String {
            s.query = Array(f)
            s.cursor = s.query.count
        }
    }

    private func present(_ s: Session) {
        if let e = configError { s.notice = "config error: " + e }
        launcher.present(s)
    }

    func showError(_ msg: String) {
        log(msg)
        let m = DmenuMode(lines: [], prompt: "mofi", message: nil, noCustom: true, format: "s")
        let s = Session(modes: [m], current: 0) { _, _ in }
        s.notice = msg
        launcher.present(s)
    }

    // MARK: IPC

    private func handle(_ req: [String: Any], _ reply: @escaping IPCServer.Reply) {
        let done: (Int, String) -> Void = { code, out in reply(["code": code, "out": out]) }
        switch req["cmd"] as? String ?? "" {
        case "ping":
            let state = launcher.visible ? "open (\(launcher.session?.mode.name ?? "?"), key window: \(launcher.panel.isKeyWindow), query: \(launcher.session?.queryString ?? ""), \(launcher.session?.filtered.count ?? 0) matches)" : "hidden"
            done(0, "mofi \(mofiVersion) pid \(getpid()), launcher \(state), \(clipboard.items.count) clipboard items")
        case "show":
            let names = strings(req["modi"]) ?? config.modi
            show(names, start: req["mode"] as? String, opts: req["opts"] as? [String: Any] ?? [:], finish: done)
        case "dmenu":
            let o = req["opts"] as? [String: Any] ?? [:]
            let lines = (req["items"] as? [Any])?.compactMap { $0 as? String } ?? []
            let m = DmenuMode(lines: lines, prompt: o["prompt"] as? String ?? config.displayName("dmenu"),
                              message: o["message"] as? String, noCustom: o["no_custom"] as? Bool ?? false,
                              format: o["format"] as? String ?? "s")
            let s = Session(modes: [m], current: 0, finish: done)
            s.requestKey = "dmenu"
            var o2 = o
            o2["message"] = nil
            o2["prompt"] = nil
            o2["no_custom"] = nil
            apply(o2, to: s)
            present(s)
        case "error":
            showError(req["message"] as? String ?? "")
            done(0, "")
        case "lua":
            do {
                let r = try lua.call("_eval", [req["code"] as? String ?? ""], results: 1)
                done(0, r.first as? String ?? "")
            } catch {
                done(1, "\(error)")
            }
        case "reload":
            if let e = reload() { done(1, e) } else { done(0, "") }
        case "quit":
            done(0, "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { NSApp.terminate(nil) }
        default:
            done(2, "unknown command")
        }
    }
}
