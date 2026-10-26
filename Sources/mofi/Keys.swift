import AppKit
import Carbon.HIToolbox

struct Mods: OptionSet, Hashable {
    let rawValue: Int
    static let ctrl = Mods(rawValue: 1)
    static let alt = Mods(rawValue: 2)
    static let shift = Mods(rawValue: 4)
    static let cmd = Mods(rawValue: 8)
}

/// A physical key plus modifiers, e.g. "ctrl-n" or "shift-Return".
struct KeySpec: Hashable {
    let code: UInt16
    let mods: Mods

    init(code: UInt16, mods: Mods) {
        self.code = code
        self.mods = mods
    }

    init(event: NSEvent) {
        code = event.keyCode
        var m: Mods = []
        let f = event.modifierFlags
        if f.contains(.control) { m.insert(.ctrl) }
        if f.contains(.option) { m.insert(.alt) }
        if f.contains(.shift) { m.insert(.shift) }
        if f.contains(.command) { m.insert(.cmd) }
        mods = m
    }

    /// Accepts mofi style ("ctrl-shift-tab") and rofi style ("Control+Shift+Tab").
    static func parse(_ s: String) -> KeySpec? {
        let lower = s.lowercased().trimmingCharacters(in: .whitespaces)
        var parts: [String] = []
        var cur = ""
        for ch in lower {
            if (ch == "-" || ch == "+") && !cur.isEmpty {
                parts.append(cur)
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { parts.append(cur) }
        guard let keyName = parts.last else { return nil }
        var mods: Mods = []
        for p in parts.dropLast() {
            switch p {
            case "ctrl", "control": mods.insert(.ctrl)
            case "alt", "option", "opt", "mod1", "meta": mods.insert(.alt)
            case "shift": mods.insert(.shift)
            case "cmd", "command", "super", "mod4", "win": mods.insert(.cmd)
            default: return nil
            }
        }
        let name = keyAliases[keyName] ?? keyName
        guard let code = keyCodes[name] else { return nil }
        return KeySpec(code: code, mods: mods)
    }

    var carbonMods: UInt32 {
        var m: UInt32 = 0
        if mods.contains(.cmd) { m |= UInt32(cmdKey) }
        if mods.contains(.shift) { m |= UInt32(shiftKey) }
        if mods.contains(.alt) { m |= UInt32(optionKey) }
        if mods.contains(.ctrl) { m |= UInt32(controlKey) }
        return m
    }
}

private let keyAliases: [String: String] = [
    "enter": "return", "ret": "return", "esc": "escape", "bs": "backspace",
    "del": "delete", "pgup": "pageup", "page_up": "pageup", "prior": "pageup",
    "pgdn": "pagedown", "page_down": "pagedown", "next": "pagedown",
    "kp_return": "kp_enter", "iso_left_tab": "tab", " ": "space",
    "bracketleft": "[", "bracketright": "]", "minus": "-", "equal": "=", "plus": "=",
    "semicolon": ";", "apostrophe": "'", "quote": "'", "comma": ",", "period": ".",
    "slash": "/", "backslash": "\\", "grave": "`", "backtick": "`",
    "arrowup": "up", "arrowdown": "down", "arrowleft": "left", "arrowright": "right",
]

/// ANSI virtual key codes (kVK_*).
let keyCodes: [String: UInt16] = {
    var m: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "backspace": 51, "escape": 53, "kp_enter": 76,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "delete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    return m
}()

enum KeyAction: String, CaseIterable {
    case accept, accept_custom, accept_alt, cancel
    case next, prev, page_next, page_prev, first, last
    case mode_next, mode_prev, delete_entry
    case backspace, delete_char, delete_word, clear_line
    case cursor_left, cursor_right, line_start, line_end, paste
}

/// System-wide hotkeys via Carbon's RegisterEventHotKey: no Accessibility
/// permission needed, and it still works on current macOS.
final class HotKeys {
    static let shared = HotKeys()
    var handler: ((UInt32) -> Void)?
    var dryRun = false
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    func install() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async { HotKeys.shared.handler?(id) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ k: KeySpec) -> UInt32? {
        let id = nextID
        nextID += 1
        if dryRun { return id }
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(k.code), k.carbonMods, EventHotKeyID(signature: OSType(0x6D6F_6669), id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else { return nil }
        refs[id] = ref
        return id
    }

    func unregisterAll() {
        for r in refs.values { UnregisterEventHotKey(r) }
        refs.removeAll()
    }
}
