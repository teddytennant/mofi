import AppKit
import CLua

/// Native functions exposed to Lua as `__mofi.*`. The public `mofi.*` API is
/// written in Lua on top of these (see Defaults.swift).
enum LuaAPI {
    static func install(_ vm: LuaVM) {
        vm.setGlobal(table: "__mofi", functions: [
            "bind": n_bind,
            "show": n_show,
            "hide": n_hide,
            "exec": n_exec,
            "shell": n_shell,
            "open": n_open,
            "notify": n_notify,
            "log": n_log,
            "reload": n_reload,
            "apps": n_apps,
            "clip_get": n_clip_get,
            "clip_set": n_clip_set,
            "clip_history": n_clip_history,
            "clip_delete": n_clip_delete,
            "clip_clear": n_clip_clear,
        ], fields: [
            "version": mofiVersion,
            "config_dir": Paths.configDir,
            "data_dir": Paths.dataDir,
        ])
    }
}

private var daemon: Daemon? { Daemon.shared }
private var live: Bool { !(Daemon.shared?.checkOnly ?? true) }

private let n_bind: LuaFn = { L in
    guard let key = LuaVM.string(L, 1) else { return LuaVM.fail(L, "key must be a string") }
    guard let spec = KeySpec.parse(key) else { return LuaVM.fail(L, "can't parse key '\(key)'") }
    guard let id = HotKeys.shared.register(spec) else {
        return LuaVM.fail(L, "can't register hotkey '\(key)' (taken by another app?)")
    }
    lua_pushinteger(L, lua_Integer(id))
    return 1
}

private let n_show: LuaFn = { L in
    let modes = strings(LuaVM.value(L, 1)) ?? []
    let opts = LuaVM.value(L, 2) as? [String: Any] ?? [:]
    guard live else { return 0 }
    // Deferred: never swap sessions or reload while Lua is mid-call.
    DispatchQueue.main.async {
        daemon?.show(modes, start: modes.first, opts: opts) { _, _ in }
    }
    return 0
}

private let n_hide: LuaFn = { _ in
    if live { DispatchQueue.main.async { daemon?.launcher.cancel() } }
    return 0
}

private let n_exec: LuaFn = { L in
    guard let cmd = LuaVM.string(L, 1) else { return 0 }
    if live { Shell.spawn(cmd) }
    return 0
}

private let n_shell: LuaFn = { L in
    guard let cmd = LuaVM.string(L, 1) else { return LuaVM.fail(L, "command must be a string") }
    let (out, code) = Shell.capture(cmd)
    LuaVM.push(L, out)
    lua_pushinteger(L, lua_Integer(code))
    return 2
}

private let n_open: LuaFn = { L in
    guard let target = LuaVM.string(L, 1) else { return 0 }
    guard live else { lua_pushboolean(L, 1); return 1 }
    var ok = true
    let p = Paths.expand(target)
    if FileManager.default.fileExists(atPath: p) {
        NSWorkspace.shared.open(URL(fileURLWithPath: p))
    } else if target.contains("://"), let url = URL(string: target) {
        ok = NSWorkspace.shared.open(url)
    } else if let app = daemon?.apps.find(target) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: .init())
    } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    } else {
        ok = false
    }
    lua_pushboolean(L, ok ? 1 : 0)
    return 1
}

private let n_notify: LuaFn = { L in
    let title = LuaVM.string(L, 1) ?? "mofi"
    let body = LuaVM.string(L, 2) ?? ""
    func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
    if live {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
    }
    return 0
}

private let n_log: LuaFn = { L in
    log("lua: " + (LuaVM.string(L, 1) ?? ""))
    return 0
}

private let n_reload: LuaFn = { _ in
    if live { DispatchQueue.main.async { daemon?.reload() } }
    return 0
}

private let n_apps: LuaFn = { L in
    guard let d = daemon else { LuaVM.push(L, [Any]()); return 1 }
    let list = d.apps.list(paths: d.config.drunPaths, exclude: d.config.drunExclude)
    LuaVM.push(L, list.map { ["name": $0.name, "path": $0.path, "bundle_id": $0.bundleID] as [String: Any] })
    return 1
}

private let n_clip_get: LuaFn = { L in
    LuaVM.push(L, NSPasteboard.general.string(forType: .string))
    return 1
}

private let n_clip_set: LuaFn = { L in
    if let s = LuaVM.string(L, 1), live { daemon?.clipboard.setText(s) }
    return 0
}

private let n_clip_history: LuaFn = { L in
    guard let store = daemon?.clipboard else { LuaVM.push(L, [Any]()); return 1 }
    LuaVM.push(L, store.items.map { item -> [String: Any] in
        var d: [String: Any] = ["kind": item.kind, "text": item.text, "time": item.time]
        if let p = store.imagePath(item) { d["image"] = p }
        return d
    })
    return 1
}

private let n_clip_delete: LuaFn = { L in
    let i = Int(mofi_tointeger(L, 1)) - 1
    if live { daemon?.clipboard.delete(i) }
    return 0
}

private let n_clip_clear: LuaFn = { _ in
    if live { daemon?.clipboard.clear() }
    return 0
}
